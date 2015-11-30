test "Can sync",
    requires => [ local_user_fixture( with_events => 0 ),
                  qw( can_create_filter )],

    provides => [qw( can_sync )],

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
       })->then( sub {
          provide can_sync => 1;

          Future->done(1);
       })
    };
