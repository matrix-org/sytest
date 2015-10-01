prepare "Create user for testing sync",
    requires => [qw(
        register_new_user first_api_client
    )],

    provides => [qw( sync_user)],

    do => sub {
        my ( $register_new_user, $http,) = @_;
        $register_new_user->( $http, "31sync_user" )->then( sub {
            my ( $sync_user ) = @_;
            provide sync_user => $sync_user;
            Future->done()
        })
    };
