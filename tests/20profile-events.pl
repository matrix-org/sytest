prepare "Flushing event stream",
   requires => [qw( flush_events_for user )],
   do => sub {
      my ( $flush_events_for, $user ) = @_;
      $flush_events_for->( $user );
   };

my $displayname = "New displayname for 20profile-events.pl";

test "Displayname change reports an event to myself",
   requires => [qw( do_request_json GET_new_events user can_set_displayname )],

   do => sub {
      my ( $do_request_json, undef, $user ) = @_;

      $do_request_json->(
         method => "PUT",
         uri    => "/profile/:user_id/displayname",

         content => { displayname => $displayname },
      );
   },

   check => sub {
      my ( undef, $GET_new_events, $user ) = @_;

      # This timeout may not be 100% reliable; if this spuriously fails try
      # making it a little bigger
      $GET_new_events->( undef, timeout => 50 )->then( sub {
         my $found;
         foreach my $event ( @_ ) {
            next unless $event->{type} eq "m.presence";
            my $content = $event->{content};
            next unless $content->{user_id} eq $user->user_id;
            $found++;

            $content->{displayname} eq $displayname or
               die "Expected displayname to be '$displayname'";
         }

         $found or
            die "Failed to find my own presence event";

         Future->done(1);
      });
   };

my $avatar_url = "http://a.new.url/for/20profile-events.pl";

test "Avatar URL change reports an event to myself",
   requires => [qw( do_request_json GET_new_events user can_set_avatar_url )],

   do => sub {
      my ( $do_request_json, undef, $user ) = @_;

      $do_request_json->(
         method => "PUT",
         uri    => "/profile/:user_id/avatar_url",

         content => { avatar_url => $avatar_url },
      );
   },

   check => sub {
      my ( undef, $GET_new_events, $user ) = @_;

      # This timeout may not be 100% reliable; if this spuriously fails try
      # making it a little bigger
      $GET_new_events->( undef, timeout => 50 )->then( sub {
         my $found;
         foreach my $event ( @_ ) {
            next unless $event->{type} eq "m.presence";
            my $content = $event->{content};
            next unless $content->{user_id} eq $user->user_id;
            $found++;

            $content->{avatar_url} eq $avatar_url or
               die "Expected avatar_url to be '$avatar_url'";
         }

         $found or
            die "Failed to find my own presence event";

         Future->done(1);
      });
   };
