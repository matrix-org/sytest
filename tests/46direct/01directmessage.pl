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
      uri     => "/unstable/sendToDevice/$type/$txn_id",
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

   my $next_batch;

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
      scalar @{ $f->get->{to_device}{events} };
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
