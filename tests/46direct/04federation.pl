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


my $FILTER_ONLY_DIRECT = '{"room":{"rooms":[]},"account_data":{"types":[]},"presence":{"types":[]}}';

test "Device messages over federation wake up /sync",
   requires => [ local_user_fixture( with_events => 0 ), remote_user_fixture() ],

   check => sub {
      my ( $local_user, $remote_user ) = @_;

      matrix_sync( $local_user,
         filter       => $FILTER_ONLY_DIRECT,
         set_presence => "offline",
      )->then( sub {
         Future->needs_all(
            matrix_sync_again( $local_user, filter => $FILTER_ONLY_DIRECT, timeout => 10000 ),
            delay(0.1)->then( sub {
               matrix_send_device_message( $remote_user,
                  type     => "my.test.type",
                  messages => {
                     $local_user->user_id => {
                        $local_user->device_id => {
                           my_key => "my_value",
                        },
                     },
                  },
               );
            }),
         );
      });
   };
