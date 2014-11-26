prepare "Flushing event stream",
   requires => [qw( flush_events_for user )],
   do => sub {
      my ( $flush_events_for, $user ) = @_;
      $flush_events_for->( $user );
   };

my $displayname = "New displayname for 20profile-events.pl";

test "Displayname change reports an event to myself",
   requires => [qw( do_request_json await_event_for user can_set_displayname )],

   do => sub {
      my ( $do_request_json, undef, $user ) = @_;

      $do_request_json->(
         method => "PUT",
         uri    => "/profile/:user_id/displayname",

         content => { displayname => $displayname },
      );
   },

   await => sub {
      my ( undef, $await_event_for, $user ) = @_;

      $await_event_for->( $user, sub {
         my ( $event ) = @_;
         return unless $event->{type} eq "m.presence";
         my $content = $event->{content};
         return unless $content->{user_id} eq $user->user_id;

         $content->{displayname} eq $displayname or
            die "Expected displayname to be '$displayname'";

         return 1;
      });
   };

my $avatar_url = "http://a.new.url/for/20profile-events.pl";

test "Avatar URL change reports an event to myself",
   requires => [qw( do_request_json await_event_for user can_set_avatar_url )],

   do => sub {
      my ( $do_request_json, undef, $user ) = @_;

      $do_request_json->(
         method => "PUT",
         uri    => "/profile/:user_id/avatar_url",

         content => { avatar_url => $avatar_url },
      );
   },

   await => sub {
      my ( undef, $await_event_for, $user ) = @_;

      $await_event_for->( $user, sub {
         my ( $event ) = @_;
         return unless $event->{type} eq "m.presence";
         my $content = $event->{content};
         return unless $content->{user_id} eq $user->user_id;

         $content->{avatar_url} eq $avatar_url or
            die "Expected avatar_url to be '$avatar_url'";

         return 1;
      });
   };

multi_test "Global /initialSync reports my own profile",
   requires => [qw( do_request_json user
                    can_set_displayname can_set_avatar_url can_initial_sync )],

   check => sub {
      my ( $do_request_json, $user ) = @_;

      $do_request_json->(
         method => "GET",
         uri    => "/initialSync",
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( presence ));
         require_json_list( $body->{presence} );

         my %presence_by_userid;
         $presence_by_userid{$_->{content}{user_id}} = $_ for @{ $body->{presence} };

         my $presence = $presence_by_userid{$user->user_id} or
            die "Failed to find my own presence information";

         require_json_keys( $presence, qw( content ) );
         require_json_keys( my $content = $presence->{content},
            qw( user_id displayname avatar_url ));

         is_eq( $content->{displayname}, $displayname, 'displayname in presence event is correct' );
         is_eq( $content->{avatar_url}, $avatar_url, 'avatar_url in presence event is correct' );

         Future->done(1);
      });
   };
