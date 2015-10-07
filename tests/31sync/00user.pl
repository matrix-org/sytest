prepare "Create user for testing sync",
    requires => [qw( first_api_client )],

    provides => [qw( sync_user )],

    do => sub {
        my ( $http,) = @_;
        matrix_register_user( $http, "31sync_user" )->then( sub {
            my ( $sync_user ) = @_;
            provide sync_user => $sync_user;
            Future->done()
        })
    };
