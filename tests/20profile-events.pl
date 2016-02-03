my $user_fixture = local_user_fixture();

my $displayname = "New displayname for 20profile-events.pl";

test "Displayname change reports an event to myself",
   requires => [ $user_fixture,
                 qw( can_set_displayname )],

   do => sub {
      my ( $user ) = @_;

      flush_events_for( $user )
      ->then( sub {
         do_request_json_for( $user,
            method => "PUT",
            uri    => "/r0/profile/:user_id/displayname",

            content => { displayname => $displayname },
         )
      })->then( sub {
         await_event_for( $user, filter => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.presence";
            my $content = $event->{content};
            return unless $content->{user_id} eq $user->user_id;

            $content->{displayname} eq $displayname or
               die "Expected displayname to be '$displayname'";

            return 1;
         });
      });
   };

my $avatar_url = "http://a.new.url/for/20profile-events.pl";

test "Avatar URL change reports an event to myself",
   requires => [ $user_fixture,
                 qw( can_set_avatar_url )],

   do => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "PUT",
         uri    => "/r0/profile/:user_id/avatar_url",

         content => { avatar_url => $avatar_url },
      )->then( sub {
         await_event_for( $user, filter => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.presence";
            my $content = $event->{content};
            return unless $content->{user_id} eq $user->user_id;

            $content->{avatar_url} eq $avatar_url or
               die "Expected avatar_url to be '$avatar_url'";

            return 1;
         });
      });
   };

test "Global /initialSync reports my own profile",
   requires => [ $user_fixture,
                 qw( can_set_displayname can_set_avatar_url can_initial_sync )],

   check => sub {
      my ( $user) = @_;

      matrix_initialsync( $user )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( presence ));
         assert_json_list( $body->{presence} );

         my %presence_by_userid;
         $presence_by_userid{ $_->{content}{user_id} } = $_ for @{ $body->{presence} };

         my $presence = $presence_by_userid{ $user->user_id } or
            die "Failed to find my own presence information";

         assert_json_keys( $presence, qw( content ) );
         assert_json_keys( my $content = $presence->{content},
            qw( user_id displayname avatar_url ));

         assert_eq( $content->{displayname}, $displayname, 'displayname in presence event is correct' );
         assert_eq( $content->{avatar_url}, $avatar_url, 'avatar_url in presence event is correct' );

         Future->done(1);
      });
   };

test "Newly-registered users have a presence state",
   requires => [ local_user_fixture() ],

   check => sub {
      my ( $user ) = @_;

      matrix_get_presence_status( $user )->then( sub {
         my ( $status ) = @_;
         log_if_fail "Status", $status;

         defined $status->{presence} or
            die "Expected 'presence' to be defined";

         !exists $status->{status_msg} or defined $status->{status_msg} or
            die "Expected 'status_msg' to be defined if it is present";

         Future->done(1);
      });
   };
