push our @EXPORT, qw( matrix_create_filter matrix_register_user_with_filter );

=head2 matrix_create_filter

    my ( $filter_id ) = matrix_create_filter( $user, \%filter )->get;

Creates a new filter for the user. Returns the filter id of the new filter.

=cut

sub matrix_create_filter {
    my ( $user, $filter ) = @_;
    do_request_json_for( $user,
        method  => "POST",
        uri     => "/v2_alpha/user/${\ $user->user_id }/filter",
        content => $filter,
    )->then( sub {
        my ( $body ) = @_;
        require_json_keys( $body, "filter_id" );
        Future->done( $body->{filter_id} )
    })
}

=head2 matrix_register_user_with_filter

    my ( $user, $filter_id ) =
        matrix_register_user_with_filter( $http, \%filter )->get;

Creates a user without an event stream and creates a filter for that user.
Returns the created C<User> object and the filter id of the new filter.

=cut

sub matrix_register_user_with_filter {
    my ( $http, $filter) = @_;
    my ( $user, $filter_id );
    matrix_register_user( $http, undef, with_events => 0)->then( sub {
        ( $user ) = @_;
        matrix_create_filter( $user, $filter );
    })->then( sub {
        ( $filter_id ) = @_;
        Future->done( $user, $filter_id )
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
