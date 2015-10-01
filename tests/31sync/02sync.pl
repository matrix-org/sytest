prepare "Helper method for syncing",
    requires => [qw( do_request_json_for )],

    provides => [qw( do_sync )],

    do => sub {
        my ( $do_request_json_for ) = @_;
        provide do_sync => sub {
            my ( $user, %params ) = @_;
            $do_request_json_for->($user,
                method  => "GET",
                uri     => "/v2_alpha/sync",
                params  => \%params,
            )
        };
        Future->done()
    };

test "Can sync",
    requires => [qw( do_sync sync_user sync_filter )],

    check => sub {
        my ( $do_sync, $sync_user, $sync_filter ) = @_;
        $do_sync->( $sync_user, filter => $sync_filter )->then(sub {
            my ( $body ) = @_;
            Future->done(1);
        })
    };
