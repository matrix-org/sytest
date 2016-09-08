test "Can recv device messages over federation",
   requires => [ local_user_fixture(), remote_user_fixture(),
      qw( can_recv_device_message ) ],

   check => sub {
      my ( $local_user, $remote_user ) = @_;

      matrix_send_device_message( $local_user,
         type     => "my.test.type",
         messages => {
            $remote_user->user_id => {
               $remote_user->device_id => {
                  message => "first",
               },
            },
         },
      )->then( sub {
         # Download the first message again and acknowledge it.
         matrix_recv_and_ack_device_message( $remote_user );
      })->then( sub {
         my ( $messages ) = @_;

         assert_deeply_eq( $messages, [{
            sender  => $local_user->user_id,
            type    => "my.test.type",
            content => {
               message => "first",
            },
         }]);

         # Send another message so that we can check that the remote user
         # doesn't receive the first message twice
         matrix_send_device_message( $local_user,
            type     => "my.test.type",
            messages => {
               $remote_user->user_id => {
                  $remote_user->device_id => {
                     message => "second",
                  },
               },
            },
         );
      })->then( sub {
         # Download the second message and acknowledge it.
         matrix_recv_and_ack_device_message( $remote_user );
      })->then( sub {
         my ( $messages ) = @_;

         assert_deeply_eq( $messages, [{
            sender  => $local_user->user_id,
            type    => "my.test.type",
            content => {
               message => "second",
            },
         }]);

         Future->done(1);
      });
   };
