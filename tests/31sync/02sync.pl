use Future::Utils qw( repeat );


test "Can sync",
    requires => [ local_user_fixture( with_events => 0 ) ],

    proves => [qw( can_sync )],

    do => sub {
       my ( $user ) = @_;

       matrix_sync( $user, timeout => 0 ) ->then( sub {
          my ( $body ) = @_;

          matrix_sync(
             $user,
             since => $body->{next_batch},
             timeout => 0,
          )
       })->then_done(1);
    };
