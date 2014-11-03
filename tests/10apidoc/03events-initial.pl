use List::UtilsBy qw( extract_by );

test "GET /events initially",
   requires => [qw( do_request_json user first_http_client )],

   check => sub {
      my ( $do_request_json, $user, $http ) = @_;

      $do_request_json->(
         method => "GET",
         uri    => "/events",
         params => { timeout => 0 },
      )->then( sub {
         my ( $body ) = @_;

         json_keys_ok( $body, qw( start end chunk ));
         json_list_ok( $body->{chunk} );

         provide can_get_events => 1;

         # We can't be absolutely sure that there won't be any events yet, so
         # don't check that.

         # Set current event-stream end point
         $user->eventstream_token = $body->{end};

         Future->done(1);
      });
   };

test "GET /initialSync initially",
   requires => [qw( do_request_json )],

   check => sub {
      my ( $do_request_json ) = @_;

      $do_request_json->(
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

prepare "Environment closures for stateful /event access",
   requires => [qw( user can_get_events )],

   do => sub {
      my ( $first_user ) = @_;

      # A useful closure, which keeps track of the current eventstream token
      # and fetches new events since it
      provide saved_events_for => my $saved_events_for = sub {
         my ( $user, $filter, @more ) = @_;
         $filter = qr/^\Q$filter\E$/ if defined $filter and not ref $filter;

         my @events = ( @{ $user->saved_events }, @more );
         my @filtered_events = extract_by { $filter ? $_->{type} =~ $filter : 1 } @events;
         $user->saved_events = \@events;

         Future->done( @filtered_events );
      };

      provide GET_new_events_for => my $GET_new_events_for = sub {
         my ( $user, $filter, %opts ) = @_;

         $user->http->do_request_json(
            method => "GET",
            uri    => "/events",
            params => {
               access_token => $user->access_token,
               from         => $user->eventstream_token,
               timeout      => $opts{timeout} // 10000,
            }
         )->then( sub {
            my ( $body ) = @_;
            $user->eventstream_token = $body->{end};

            return $saved_events_for->( $user, $filter, @{ $body->{chunk} } );
         });
      };

      provide flush_events_for => sub {
         my ( $user ) = @_;

         $user->http->do_request_json(
            method => "GET",
            uri    => "/events",
            params => {
               access_token => $user->access_token,
               timeout      => 0,
            }
         )->then( sub {
            my ( $body ) = @_;
            $user->eventstream_token = $body->{end};
            @{ $user->saved_events } = ();

            Future->done;
         });
      };


      # Convenient wrapper operating on the first user
      provide GET_new_events => sub {
         $GET_new_events_for->( $first_user, @_ );
      };

      Future->done(1);
   };
