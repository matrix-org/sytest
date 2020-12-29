test "Can send messages with a wildcard device id",
   requires => [ local_user_fixture(), qw( can_recv_device_message ) ],

   check => sub {
      my ( $user ) = @_;

      matrix_send_device_message( $user,
         type     => "my.test.type",
         messages => {
            $user->user_id => {
               "*" => {
                  message => "first",
               },
            },
         },
      )->then( sub {
         # Download the first message again and acknowledge it.
         matrix_recv_and_ack_device_message( $user );
      })->then( sub {
         my ( $messages ) = @_;

         assert_deeply_eq( $messages, [{
            sender  => $user->user_id,
            type    => "my.test.type",
            content => {
               message => "first",
            },
         }]);

         # Send another message so that we can check that the user
         # doesn't receive the first message twice
         matrix_send_device_message( $user,
            type     => "my.test.type",
            messages => {
               $user->user_id => {
                  "*" => {
                     message => "second",
                  },
               },
            },
         );
      })->then( sub {
         # Download the second message and acknowledge it.
         matrix_recv_and_ack_device_message( $user );
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

test "Can send messages with a wildcard device id to two devices",
   requires => [ local_user_fixture(), qw( can_recv_device_message ) ],

   check => sub {
      my ( $user_device1 ) = @_;
      my ( $user_device2 );

      matrix_login_again_with_user( $user_device1 )->then( sub {
         ( $user_device2 ) = @_;

         matrix_send_device_message( $user_device1,
            type     => "my.test.type",
            messages => {
               $user_device1->user_id => {
                  "*" => {
                     message => "first",
                  },
               },
            },
         );
      })->then( sub {
         # Download the first message again and acknowledge it.
         Future->needs_all(
            matrix_recv_and_ack_device_message( $user_device1 ),
            matrix_recv_and_ack_device_message( $user_device2 ),
         );
      })->then( sub {
         my ( $messages_1, $messages_2 ) = @_;

         assert_deeply_eq( $messages_1, [{
            sender  => $user_device1->user_id,
            type    => "my.test.type",
            content => {
               message => "first",
            },
         }]);

         assert_deeply_eq( $messages_1, $messages_2 );

         # Send another message so that we can check that the user
         # doesn't receive the first message twice
         matrix_send_device_message( $user_device1,
            type     => "my.test.type",
            messages => {
               $user_device1->user_id => {
                  "*" => {
                     message => "second",
                  },
               },
            },
         );
      })->then( sub {
         # Download the second message and acknowledge it.
         Future->needs_all(
            matrix_recv_and_ack_device_message( $user_device1 ),
            matrix_recv_and_ack_device_message( $user_device2 ),
         );
      })->then( sub {
         my ( $messages_1, $messages_2 ) = @_;

         assert_deeply_eq( $messages_1, [{
            sender  => $user_device1->user_id,
            type    => "my.test.type",
            content => {
               message => "second",
            },
         }]);

         assert_deeply_eq( $messages_1, $messages_2 );

         Future->done(1);
      });
   };


my $FILTER_ONLY_DIRECT = '{"room":{"rooms":[]},"account_data":{"types":[]},"presence":{"types":[]}}';

test "Wildcard device messages wake up /sync",
   requires => [ local_user_fixture( with_events => 0 ) ],

   check => sub {
      my ( $user ) = @_;

      matrix_sync( $user,
         filter       => $FILTER_ONLY_DIRECT,
         set_presence => "offline",
      )->then( sub {
         Future->needs_all(
            matrix_sync_again( $user, filter => $FILTER_ONLY_DIRECT, timeout => 10000 * $TIMEOUT_FACTOR ),
            delay(0.1 * $TIMEOUT_FACTOR)->then( sub {
               matrix_send_device_message( $user,
                  type     => "my.test.type",
                  messages => {
                     $user->user_id => {
                        "*" => {
                           my_key => "my_value",
                        },
                     },
                  },
               );
            }),
         );
      });
   };


test "Wildcard device messages over federation wake up /sync",
   requires => [ local_user_fixture( with_events => 0 ), remote_user_fixture() ],

   check => sub {
      my ( $local_user, $remote_user ) = @_;

      matrix_sync( $local_user,
         filter       => $FILTER_ONLY_DIRECT,
         set_presence => "offline",
      )->then( sub {
         Future->needs_all(
            matrix_sync_again( $local_user, filter => $FILTER_ONLY_DIRECT, timeout => 10000 * $TIMEOUT_FACTOR ),
            delay(0.1 * $TIMEOUT_FACTOR)->then( sub {
               matrix_send_device_message( $remote_user,
                  type     => "my.test.type",
                  messages => {
                     $local_user->user_id => {
                        "*" => {
                           my_key => "my_value",
                        },
                     },
                  },
               );
            }),
         );
      });
   };
