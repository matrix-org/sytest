prepare "Flushing event stream",
   requires => [qw( flush_events_for user )],
   do => sub {
      my ( $flush_events_for, $user ) = @_;
      $flush_events_for->( $user );
   };

test "initialSync sees my presence status",
   requires => [qw( do_request_json user can_initial_sync )],

   check => sub {
      my ( $do_request_json, $user ) = @_;

      $do_request_json->(
         method => "GET",
         uri    => "/initialSync",
      )->then( sub {
         my ( $body ) = @_;

         json_keys_ok( $body, qw( presence ));

         my $found;

         foreach my $event ( @{ $body->{presence} } ) {
            json_object_ok( $event, qw( type content ));
            $event->{type} eq "m.presence" or
               die "Expected type of event to be m.presence";

            my $content = $event->{content};
            json_object_ok( $content, qw( user_id presence last_active_ago ));

            next unless $content->{user_id} eq $user->user_id;

            $found = 1;
         }

         $found or
            die "Did not find an initial presence message about myself";

         Future->done(1);
      });
   };

my $status_msg = "A status set by 21presence-events.pl";

test "Presence change reports an event to myself",
   requires => [qw( do_request_json GET_new_events user can_set_presence )],

   do => sub {
      my ( $do_request_json ) = @_;

      $do_request_json->(
         method => "PUT",
         uri    => "/presence/:user_id/status",

         content => { presence => "online", status_msg => $status_msg },
      )
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

            $content->{status_msg} eq $status_msg or
               die "Expected status_msg to be '$status_msg'";
         }

         $found or
            die "Failed to find my own presence event";

         Future->done(1);
      });
   };
