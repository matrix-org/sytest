my $displayname = "Another name here";

test "GET /events sees profile change",
   requires => [qw( do_request_json_authed GET_events_after user_id
                    can_set_displayname )],

   do => sub {
      my ( $do_request_json_authed, $GET_events_after, $user_id ) = @_;

      $GET_events_after->( sub {
         $do_request_json_authed->(
            method => "PUT",
            uri    => "/profile/:user_id/displayname",

            content => {
               displayname => $displayname,
            }
         )
      })->then( sub {
         my $found_me;

         foreach my $event ( @_ ) {
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
