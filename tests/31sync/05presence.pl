use List::Util qw( first );

test "User sees their own presence in a sync",
    requires => [qw( first_api_client can_sync )],
    
    check => sub {
        my ( $http ) = @_;
        my ( $user, $filter_id );
        matrix_register_sync_user( $http )->then( sub {
            ( $user ) = @_;
            matrix_create_filter( $user, {} )
        })->then( sub {
            matrix_sync( $user, filter => $filter_id )
        })->then( sub {
            my ( $body ) = @_;
            my $events = $body->{presence}{events};
            my $presence = first { $_->{type} eq "m.presence" } @$events;
            defined $presence or die "Expected to see our own presence";
            $presence->{sender} eq $user->user_id or die "Unexpected sender";
            $presence->{content}{presence} eq "online"
                or die "Expected to be online";
            Future->done(1)
        })
    };

test "User is offline if they set_presence=offline in their sync",
    requires => [qw( first_api_client can_sync )],
    
    check => sub {
        my ( $http ) = @_;
        my ( $user, $filter_id );
        matrix_register_sync_user( $http )->then( sub {
            ( $user ) = @_;
            matrix_create_filter( $user, {} )
        })->then( sub {
            matrix_sync( $user, filter => $filter_id, set_presence => "offline")
        })->then( sub {
            my ( $body ) = @_;
            my $events = $body->{presence}{events};
            my $presence = first { $_->{type} eq "m.presence" } @$events;
            defined $presence or die "Expected to see our own presence";
            $presence->{sender} eq $user->user_id or die "Unexpected sender";
            $presence->{content}{presence} eq "offline"
                or die "Expected to be offline";
            Future->done(1)
        })
    };
