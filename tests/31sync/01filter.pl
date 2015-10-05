prepare "Helper method for creating filters",
    requires => [qw( do_request_json_for )],

    provides => [qw( create_filter )],

    do => sub {
        my ( $do_request_json_for ) = @_;
        provide create_filter => sub {
            my ( $user, $filter ) = @_;
            $do_request_json_for->($user,
                method  => "POST",
                uri     => "/v2_alpha/user/${\$user->user_id}/filter",
                content => $filter,
            )->then( sub {
                my ( $body ) = @_;
                require_json_keys($body, "filter_id");
                Future->done($body->{filter_id})
            })
        };
        Future->done()
    };

test "Can create filter",
    requires => [qw( sync_user create_filter )],

    provides => [qw( sync_filter )],

    do => sub {
        my ( $sync_user, $create_filter ) = @_;
        $create_filter->( $sync_user, {
            room => { timeline => { limit => 10 } },
        })->then( sub {
            my ( $sync_filter ) = @_;
            provide sync_filter => $sync_filter;
            Future->done()
        });
    };

test "Can download filter",
    requires => [qw ( do_request_json_for sync_user sync_filter )],

    check => sub {
        my ( $do_request_json_for, $sync_user, $sync_filter ) = @_;
        $do_request_json_for->( $sync_user,
            method  => "GET",
            uri     => "/v2_alpha/user/${\$sync_user->user_id}/filter/$sync_filter",
        )->then( sub {
            my ( $body ) = @_;
            require_json_keys( $body, "room" );
            require_json_keys( my $room = $body->{room}, "timeline" );
            require_json_keys( my $timeline = $room->{timeline}, "limit" );
            $timeline->{limit} eq 10 or die "Expected timeline limit to be 10";
            Future->done(1)
        })
    };
