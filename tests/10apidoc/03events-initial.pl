use List::UtilsBy qw( extract_by );
use Future::Utils qw( repeat );

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

         require_json_keys( $body, qw( start end chunk ));
         require_json_list( $body->{chunk} );

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

         require_json_keys( $body, qw( end ));

         # Spec says these are optional
         if( exists $body->{rooms} ) {
            require_json_list( $body->{rooms} );
         }
         if( exists $body->{presence} ) {
            require_json_list( $body->{presence} );
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

      my $GET_new_events_for = sub {
         my ( $user ) = @_;

         return $user->pending_get_events //=
            $user->http->do_request_json(
               method => "GET",
               uri    => "/events",
               params => {
                  access_token => $user->access_token,
                  from         => $user->eventstream_token,
                  timeout      => 500,
               }
            )->on_ready( sub {
               undef $user->pending_get_events;
            })->then( sub {
               my ( $body ) = @_;
               $user->eventstream_token = $body->{end};

               my @events = ( @{ $user->saved_events }, @{ $body->{chunk} } );
               @{ $user->saved_events } = ();

               Future->done( @events );
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

      provide await_event_for => sub {
         my ( $user, $filter ) = @_;

         repeat {
            # Just replay saved ones the first time around, if there are any
            my $replay_saved = !shift && scalar @{ $user->saved_events };

            ( $replay_saved
               ? Future->done( @{ $user->saved_events } )
               : $GET_new_events_for->( $user )
            )->then( sub {
               my $found;
               foreach my $event ( @_ ) {
                  not $found and $filter->( $event ) and
                     $found = 1, next;

                  # Save it for later
                  push @{ $user->saved_events }, $event;
               }

               Future->done( $found );
            });
         } while => sub { !$_[0]->failure and !$_[0]->get };
      };

      Future->done(1);
   };
