use Future::Utils qw( repeat );


test "Can sync",
    requires => [ local_user_fixture( with_events => 0 ),
                  qw( can_create_filter )],

    proves => [qw( can_sync )],

    do => sub {
       my ( $user ) = @_;

       my $filter_id;

       matrix_create_filter( $user, {} )->then( sub {
          ( $filter_id ) = @_;

          matrix_sync( $user, filter => $filter_id )
       })->then( sub {
          my ( $body ) = @_;

          matrix_sync( $user,
             filter => $filter_id,
             since => $body->{next_batch},
          )
       })->then_done(1);
    };
