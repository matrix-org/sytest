my $matrix_send_to_device_message_txn_id = 0;

push our @EXPORT, qw( matrix_send_to_device_message );

sub matrix_send_to_device_message
{
   my ( $user, %params ) = @_;
   exists $params{type} or die "Expected a type";
   exists $params{messages} or die "Expected messages";
   my $type = delete $params{type};
   my $txn_id = delete $params{txn_id} // ++$matrix_send_to_device_message_txn_id;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/unstable/sendToDevice/$type/$txn_id",
      content => \%params,
   );
}

test "Can send a to_device message using PUT",
   requires => [ local_user_fixture() ],
   provides => [ qw( can_send_to_device_message ) ],

   check => sub {
      my ( $user ) = @_;

      matrix_send_to_device_message( $user,
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

push @EXPORT, qw( matrix_recv_to_device_message );

sub matrix_recv_to_device_message
{
   my ( $user ) = @_;

   my $next_batch;

   my $f = repeat {
      matrix_sync( $user,
         filter            => $FILTER_ONLY_DIRECT,
         update_next_batch => 0,
         set_presence      => "offline",
      );
   } until => sub {
      my ( $f ) = @_;
      return 1 if $f->failure;
      $f->get->{to_device}{events};
   };

   $f->then( sub {
      my ( $body ) = @_;

      assert_json_keys( $body, qw( to_device ) );
      assert_json_keys( $body->to_device, qw( events ) );
      my $messages = $body->{to_device}{events};

      Future->done( $messages, $body->{next_batch} );
   });
}

push @EXPORT, qw( matrix_ack_to_device_message );

sub matrix_ack_to_device_messsage
{
   my ( $user, $next_batch ) = @_;

   matrix_sync( $user,
      filter            => $FILTER_ONLY_DIRECT,
      since             => $next_batch,
      update_next_batch => 0,
      set_presence      => "offline",
   );
}

push @EXPORT, qw( matrix_recv_and_ack_to_device_message );

sub matrix_recv_and_ack_to_device_messsage
{
   my ( $user ) = @_;

   matrix_recv_to_device_messsage( $user )->then( sub {
      my ( $messages, $next_batch ) = @_;

      matrix_ack_to_device_message( $user, $next_batch )->then( sub {
         Future->done( $messages );
      });
   });
}


test "Can recv a to_device message using /sync",
   requires => [ local_user_fixture(), qw( can_send_to_device_message ) ],
   provides => [ qw( can_recv_to_device_message ) ],

   check => sub {
      my ( $user ) = @_;

      matrix_send_to_device_message( $user,
         type     => "my.test.type",
         messages => {
            $user->user_id => {
               $user->device_id => {
                  my_key => "my_value",
               },
            },
         },
      )->then( sub {
         matrix_recv_and_ack_to_device_message( $user );
      })->then( sub {
         my ( $messages ) = @_;

         assert_deeply_eq( $messages, [{
            sender  => $user->user_id,
            type    => "my.test.type",
            content => {
               my_key => "my_value",
            },
         }]);
      });
   };
