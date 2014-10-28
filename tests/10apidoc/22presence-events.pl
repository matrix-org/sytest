
test "GET /initialSync sees status",
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
