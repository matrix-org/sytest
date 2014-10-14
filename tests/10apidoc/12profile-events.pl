my $displayname = "Another name here";

test "GET /events sees profile change",
   requires => [qw( first_http_client can_login can_set_displayname )],

   prepare => sub {
      my ( $http, $login ) = @_;
      my ( undef, $access_token ) = @$login;

      $http->GET_current_event_token( $access_token );
   },

   do => sub {
      my ( $http, $login, undef, $before_event_token ) = @_;
      my ( $user_id, $access_token ) = @$login;

      $http->do_request_json(
         method => "PUT",
         uri    => "/profile/$user_id/displayname",
         params => { access_token => $access_token },

         content => {
            displayname => $displayname,
         }
      )->then( sub {
         $http->do_request_json(
            method => "GET",
            uri    => "/events",
            params => { access_token => $access_token, from => $before_event_token, timeout => 10000 },
         )
      })->then( sub {
         my ( $body ) = @_;

         $body->{start} eq $before_event_token or die "Expected 'start' to be before_event_token\n";

         my $found_me;

         foreach my $event ( @{ $body->{chunk} } ) {
            defined $event->{type} or die "Expected event to contain 'type' key\n";
            next unless $event->{type} eq "m.presence";

            defined $event->{content} or die "Expected m.presence event to contain 'content' key\n";
            my $content = $event->{content};

            defined $content->{user_id} or die "Expected m.presence content to contain 'user_id' key\n";
            next unless $content->{user_id} eq $user_id;

            $found_me = 1;

            defined $content->{displayname} or die "Expected m.presence to contain 'displayname' key\n";
            $content->{displayname} eq $displayname or die "Expected displayname to be '$displayname'\n";
         }

         $found_me or
            die "Did not find an appropriate presence event\n";

         Future->done(1);
      });
   };
