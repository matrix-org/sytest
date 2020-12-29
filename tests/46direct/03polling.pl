my $FILTER_ONLY_DIRECT = '{"room":{"rooms":[]},"account_data":{"types":[]},"presence":{"types":[]}}';

test "Device messages wake up /sync",
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
                        $user->device_id => {
                           my_key => "my_value",
                        },
                     },
                  },
               );
            }),
         );
      });
   };
