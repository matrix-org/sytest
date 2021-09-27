use Future::Utils qw( repeat );

my $next_device_message_txn_id = 0;

push our @EXPORT, qw( matrix_send_device_message );

sub matrix_send_device_message
{
   my ( $user, %params ) = @_;
   exists $params{messages} or die "Expected messages";
   my $type = delete $params{type} or die "Expected a type";
   my $txn_id = delete $params{txn_id} // $next_device_message_txn_id++;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/r0/sendToDevice/$type/$txn_id",
      content => \%params,
   );
}

test "Can send a message directly to a device using PUT /sendToDevice",
   requires => [ local_user_fixture() ],

   proves => [ qw( can_send_device_message ) ],

   check => sub {
      my ( $user ) = @_;

      matrix_send_device_message( $user,
         type     => "my.test.type",
         messages => {
            $user->user_id => {
               $user->device_id => {
                  my_key => "my_value",
               },
            },
         },
      );
   };


my $FILTER_ONLY_DIRECT = '{"room":{"rooms":[]},"account_data":{"types":[]},"presence":{"types":[]}}';

push @EXPORT, qw( matrix_recv_device_message );

sub matrix_recv_device_message
{
   my ( $user ) = @_;

   my $delay = 0;

   my $f = repeat {
      delay( $delay )->then( sub {
         $delay = 0.1 + $delay * 1.5;

         my @params = (
            filter            => $FILTER_ONLY_DIRECT,
            update_next_batch => 0,
            set_presence      => "offline",
         );

         if( defined $user->device_message_next_batch ) {
            push @params, since => $user->device_message_next_batch;
         }

         matrix_sync( $user, @params );
      });
   } until => sub {
      my ( $f ) = @_;
      return 1 if $f->failure;
      my $resp = $f->get;
      log_if_fail "Sync response", $resp;
      if( exists $resp->{to_device} and exists $resp->{to_device}{events} ) {
        return scalar @{ $resp->{to_device}{events} };
      }
   };

   $f->then( sub {
      my ( $body ) = @_;

      assert_json_keys( $body, qw( to_device ) );
      assert_json_keys( $body->{to_device}, qw( events ) );
      my $messages = $body->{to_device}{events};

      Future->done( $messages, $body->{next_batch} );
   });
}

push @EXPORT, qw( matrix_ack_device_message );

sub matrix_ack_device_message
{
   my ( $user, $next_batch ) = @_;

   matrix_sync( $user,
      filter            => $FILTER_ONLY_DIRECT,
      since             => $next_batch,
      update_next_batch => 0,
      set_presence      => "offline",
   )->then_with_f( sub {
      my ( $f, $body ) = @_;

      $user->device_message_next_batch = $body->{next_batch};

      return $f;
   })
}

push @EXPORT, qw( matrix_recv_and_ack_device_message );

sub matrix_recv_and_ack_device_message
{
   my ( $user ) = @_;

   matrix_recv_device_message( $user )->then( sub {
      my ( $messages, $next_batch ) = @_;

      matrix_ack_device_message( $user, $next_batch )->then( sub {
         Future->done( $messages );
      });
   });
}


test "Can recv a device message using /sync",
   requires => [ local_user_fixture(), qw( can_send_device_message ) ],

   proves => [ qw( can_recv_device_message ) ],

   check => sub {
      my ( $user ) = @_;

      matrix_send_device_message( $user,
         type     => "my.test.type",
         messages => {
            $user->user_id => {
               $user->device_id => {
                  my_key => "my_value",
               },
            },
         },
      )->then( sub {
         matrix_recv_and_ack_device_message( $user );
      })->then( sub {
         my ( $messages ) = @_;

         assert_deeply_eq( $messages, [{
            sender  => $user->user_id,
            type    => "my.test.type",
            content => {
               my_key => "my_value",
            },
         }]);

         Future->done(1);
      });
   };

test "Can send a to-device message to two users which both receive it using /sync",
   requires => [ local_user_fixture(), local_user_fixture(), local_user_fixture(), qw( can_recv_device_message ) ],

   check => sub {
      my ( $sender, $recip1, $recip2 ) = @_;

      # do initial syncs for each recipient
      matrix_sync( $recip1 )
      ->then( sub {
         my ( $body ) = @_;
         $recip1->device_message_next_batch = $body->{next_batch};

         matrix_sync( $recip2 );
      })->then( sub {
         my ( $body ) = @_;
         $recip2->device_message_next_batch = $body->{next_batch};

         # send the message
         matrix_send_device_message(
            $sender,
            type     => "my.test.type",
            messages => {
               $recip1->user_id => {
                  $recip1->device_id => {
                     my_key => "r1",
                  },
               },
               $recip2->user_id => {
                  $recip2->device_id => {
                     my_key => "r2",
                  },
               },
            },
         );
      })->then( sub {
         log_if_fail "sent to-device messages";
         matrix_recv_and_ack_device_message( $recip1 );
      })->then( sub {
         my ( $messages ) = @_;

         assert_deeply_eq( $messages, [{
            sender  => $sender->user_id,
            type    => "my.test.type",
            content => { my_key => "r1" },
         }]);

         matrix_recv_and_ack_device_message( $recip2 );
      })->then( sub {
         my ( $messages ) = @_;

         assert_deeply_eq( $messages, [{
            sender  => $sender->user_id,
            type    => "my.test.type",
            content => { my_key => "r2" },
         }]);

         Future->done(1);
      });
   };
