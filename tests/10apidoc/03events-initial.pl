test "GET /events initially",
   requires => [qw( do_request_json_authed )],

   check => sub {
      my ( $do_request_json_authed ) = @_;

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

         provide GET_current_event_token => my $get_current = sub {
            $do_request_json_authed->(
               method => "GET",
               uri    => "/events",
               params => { from => "END", timeout => 0 },
            )->then( sub {
               my ( $body ) = @_;
               Future->done( $body->{end} );
            });
         };

         # A useful closure for other tests to use, returning the next chunk
         # of events that occur after some code is run
         provide GET_events_after => sub {
            my ( $code ) = @_;

            my $before_event_token;
            $get_current->()->then( sub {
               ( $before_event_token ) = @_;

               $code->()
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

               json_list_ok( $body->{chunk} );

               Future->done( @{ $body->{chunk} } );
            });
         };

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
