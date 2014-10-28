test "GET /events initially",
   requires => [qw( do_request_json_authed user first_http_client )],

   check => sub {
      my ( $do_request_json_authed, $user, $http ) = @_;

      $do_request_json_authed->(
         method => "GET",
         uri    => "/events",
         params => { timeout => 0 },
      )->then( sub {
         my ( $body ) = @_;

         json_keys_ok( $body, qw( start end chunk ));
         ref $body->{chunk} eq "ARRAY" or die "Expected 'chunk' as a JSON list\n";

         # We can't be absolutely sure that there won't be any events yet, so
         # don't check that.

         # A useful closure, which keeps track of the current eventstream token
         # and fetches new events since it
         provide GET_new_events_for_user => my $GET_new_events_for_user = sub {
            my ( $user, $filter ) = @_;
            $filter = qr/^\Q$filter\E$/ if defined $filter and not ref $filter;

            $http->do_request_json(
               method => "GET",
               uri    => "/events",
               params => {
                  access_token => $user->access_token,
                  from         => $user->eventstream_token,
                  timeout      => 10000,
               }
            )->then( sub {
               my ( $body ) = @_;
               $user->eventstream_token = $body->{end};

               if( defined $filter ) {
                  Future->done( grep { $_->{type} =~ $filter } @{ $body->{chunk} } );
               }
               else {
                  Future->done( @{ $body->{chunk} } );
               }
            });
         };

         # Convenient wrapper operating on the first user
         provide GET_new_events => sub {
            $GET_new_events_for_user->( $user, @_ );
         };

         # Set current event-stream end point
         $user->eventstream_token = $body->{end};

         Future->done(1);
      });
   };

test "GET /initialSync initially",
   requires => [qw( do_request_json_authed )],

   check => sub {
      my ( $do_request_json_authed ) = @_;

      $do_request_json_authed->(
         method => "GET",
         uri    => "/initialSync",
      )->then( sub {
         my ( $body ) = @_;

         json_keys_ok( $body, qw( end ));

         # Spec says these are optional
         if( exists $body->{rooms} ) {
            json_list_ok( $body->{rooms} );
         }
         if( exists $body->{presence} ) {
            json_list_ok( $body->{presence} );
         }

         provide can_initial_sync => 1;

         Future->done(1);
      });
   };
