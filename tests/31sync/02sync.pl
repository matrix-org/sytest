push our @EXPORT, qw( matrix_sync );

sub matrix_sync {
    my ( $user, %params ) = @_;
    do_request_json_for( $user,
        method  => "GET",
        uri     => "/v2_alpha/sync",
        params  => \%params,
    )->on_done(sub {
        my ( $body ) = @_;
        require_json_keys( $body, qw( rooms room_map presence next_batch ) );
        require_json_keys( my $rooms = $body->{rooms}, qw( default ));
        require_json_keys( $rooms->{default}, qw( joined invited archived ) );
    });
}

test "Can sync",
    requires => [qw( sync_user can_create_filter )],
    provides => [qw( can_sync )],

    check => sub {
        my (  $sync_user ) = @_;

        my $sync_filter;

        my $check_empty_sync = sub {
            my ( $body ) = @_;
        };

        matrix_create_filter( $sync_user, {
            room => { timeline => { limit => 10 } }
        })->then( sub {
            ( $sync_filter ) = @_;
            matrix_sync( $sync_user, filter => $sync_filter )
        })->then( sub {
            my ( $body ) = @_;
            matrix_sync( $sync_user,
                filter => $sync_filter,
                since => $body->{next_batch},
            )
        })->then( sub {
            provide can_sync => 1;
            Future->done(1);
        })
    };
