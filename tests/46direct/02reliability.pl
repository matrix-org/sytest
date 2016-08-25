test "Can recv to_device messages until they are acknowledged",
   requires => [ local_user_fixture(), qw( can_recv_to_device_message ) ],

   check => sub {
      my ( $user ) = @_;

      matrix_send_to_device_message( $user,
         type     => "my.test.type",
         messages => {
            $user->user_id => {
               $user->device_id => {
                  message => "first",
               },
            },
         },
      )->then( sub {
         # Download the first message but don't acknowledge it.
         matrix_recv_to_device_message( $user );
      })->then( sub {
         my ( $messages ) = @_;

         assert_deeply_eq( $messages, [{
            sender  => $user->user_id,
            type    => "my.test.type",
            content => {
               message => "first",
            },
         }]);

         # Download the first message again and acknowledge it.
         matrix_recv_and_ack_to_device_message( $user );
      })->then( sub {
         my ( $messages ) = @_;

         assert_deeply_eq( $messages, [{
            sender  => $user->user_id,
            type    => "my.test.type",
            content => {
               message => "first",
            },
         }]);

         matrix_send_to_device_message( $user,
            type     => "my.test.type",
            messages => {
               $user->user_id => {
                  $user->device_id => {
                     message => "second",
                  },
               },
            },
         );
      })->then( sub {
         # Download the second message and acknowledge it.
         matrix_recv_and_ack_to_device_message( $user );
      })->then( sub {
         my ( $messages ) = @_;

         assert_deeply_eq( $messages, [{
            sender  => $user->user_id,
            type    => "my.test.type",
            content => {
               message => "second",
            },
         }]);

         Future->done(1);
      });
   };


test "Messages with the same txn_id are deduplicated",
   requires => [ local_user_fixture(), qw( can_recv_to_device_message ) ],

   check => sub {
      my ( $user ) = @_;

      matrix_send_to_device_message( $user,
         type     => "my.test.type",
         txn_id   => "my_transaction_id",
         messages => {
            $user->user_id => {
               $user->device_id => {
                  message => "first",
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
               message => "first",
            },
         }]);

         # Send the first message again.
         # The server should ignore it because it has the same txn_id.
         matrix_send_to_device_message( $user,
            type     => "my.test.type",
            txn_id   => "my_transaction_id",
            messages => {
               $user->user_id => {
                  $user->device_id => {
                     message => "first",
                  },
               },
            },
         );
      })->then( sub {
         # Send another to_device message so that we can check that we receive it
         # rather than a duplicate of the first message.
         matrix_send_to_device_message( $user,
            type     => "my.test.type",
            messages => {
               $user->user_id => {
                  $user->device_id => {
                     message => "second",
                  },
               },
            },
         );
      })->then( sub {
         # Download the second message and acknowledge it.
         matrix_recv_and_ack_to_device_message( $user );
      })->then( sub {
         my ( $messages ) = @_;

         assert_deeply_eq( $messages, [{
            sender  => $user->user_id,
            type    => "my.test.type",
            content => {
               message => "second",
            },
         }]);

         Future->done(1);
      });
   };
