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
