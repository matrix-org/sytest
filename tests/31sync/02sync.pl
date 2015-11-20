test "Can sync",
    requires => [qw( first_api_client can_create_filter )],

    provides => [qw( can_sync )],

    do => sub {
       my ( $http ) = @_;

       my ( $user, $filter_id );

       matrix_register_user_with_filter( $http, {} )->then( sub {
          ( $user, $filter_id ) = @_;

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
