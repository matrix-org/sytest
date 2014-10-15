my $displayname = "Another name here";

test "GET /events sees profile change",
   requires => [qw( do_request_json_authed GET_current_event_token user_id
                    can_set_displayname )],

   do => sub {
      my ( $do_request_json_authed, $GET_current_event_token, $user_id ) = @_;

      my $before_event_token;

      $GET_current_event_token->()->then( sub {
         ( $before_event_token ) = @_;

         $do_request_json_authed->(
            method => "PUT",
            uri    => "/profile/:user_id/displayname",

            content => {
               displayname => $displayname,
            }
         )
      })->then( sub {
         $do_request_json_authed->(
            method => "GET",
            uri    => "/events",
            params => { from => $before_event_token, timeout => 10000 },
         )
      })->then( sub {
         my ( $body ) = @_;

         json_keys_ok( $body, qw( start end chunk ));
         $body->{start} eq $before_event_token or die "Expected 'start' to be before_event_token\n";

         my $found_me;

         foreach my $event ( @{ $body->{chunk} } ) {
            json_keys_ok( $event, qw( type content ));
            next unless $event->{type} eq "m.presence";

            my $content = $event->{content};
            json_keys_ok( $content, qw( user_id ));

            next unless $content->{user_id} eq $user_id;

            $found_me = 1;

            json_keys_ok( $content, qw( displayname ));
            $content->{displayname} eq $displayname or die "Expected displayname to be '$displayname'\n";
         }

         $found_me or
            die "Did not find an appropriate presence event\n";

         Future->done(1);
      });
   };
