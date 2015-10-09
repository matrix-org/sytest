push our @EXPORT, qw( matrix_create_filter );


sub matrix_create_filter {
    my ( $user, $filter ) = @_;
    do_request_json_for( $user,
        method  => "POST",
        uri     => "/v2_alpha/user/${\ $user->user_id }/filter",
        content => $filter,
    )->then( sub {
        my ( $body ) = @_;
        require_json_keys($body, "filter_id");
        Future->done($body->{filter_id})
    })
}


test "Can create filter",
    requires => [qw( first_api_client )],

    provides => [qw( can_create_filter )],

    do => sub {
        my ( $http ) = @_;
        matrix_register_user( $http, undef, with_events => 0 )->then( sub {
            my ( $user ) = @_;
            matrix_create_filter( $user, {
                room => { timeline => { limit => 10 } },
            })
        })->on_done( sub {
            provide can_create_filter => 1
        })
    };


test "Can download filter",
    requires => [qw ( first_api_client can_create_filter )],

    check => sub {
        my ( $http ) = @_;
        my $user;
        matrix_register_user( $http, undef, with_events => 0 )->then( sub {
            ( $user ) = @_;
            matrix_create_filter( $user, {
                room => { timeline => { limit => 10 }}
            })
        })->then( sub {
            my ( $filter_id ) = @_;
            do_request_json_for( $user,
                method  => "GET",
                uri     => "/v2_alpha/user/${\ $user->user_id }/filter/$filter_id",
            )
        })->then( sub {
            my ( $body ) = @_;
            require_json_keys( $body, "room" );
            require_json_keys( my $room = $body->{room}, "timeline" );
            require_json_keys( my $timeline = $room->{timeline}, "limit" );
            $timeline->{limit} eq 10 or die "Expected timeline limit to be 10";
            Future->done(1)
        })
    };
