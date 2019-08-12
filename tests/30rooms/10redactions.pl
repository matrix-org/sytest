use URI::Escape qw( uri_escape );

sub make_room_and_message
{
   my ( $users, $sender ) = @_;

   my $room_id;
   matrix_create_and_join_room( $users )->then( sub {
      ( $room_id ) = @_;

      matrix_send_room_message( $sender, $room_id,
         content => { msgtype => "m.message", body => "orangutans are not monkeys" },
      )
   })->then( sub {
      my ( $event_id ) = @_;

      return Future->done( $room_id, $event_id );
   });
}

=head2 matrix_redact_event

   my $redaction_event_id = matrix_redact_event(
      $user, $room_id, $event_id, %params
   )->get;

Makes a /redact request

=cut

sub matrix_redact_event
{
   my ( $user, $room_id, $event_id, %params ) = @_;

   $room_id = uri_escape( $room_id );
   my $esc_event_id = uri_escape( $event_id );

   do_request_json_for( $user,
      method => "POST",
      uri    => "/r0/rooms/$room_id/redact/$esc_event_id",
      content => \%params,
   )->then( sub {
      my ( $body ) = @_;

      log_if_fail "Sent redaction for $event_id", $body;
      return Future->done( $body->{ event_id } );
   });
}

push our @EXPORT, qw( matrix_redact_event );

=head2 matrix_redact_event_synced

   my $redaction_event_id = matrix_redact_event_synced(
      $user, $room_id, $event_id, %params
   )->get;

Makes a /redact request and waits for it to be echoed back in a sync

=cut

sub matrix_redact_event_synced
{
   my ( $user, $room_id, $event_id, %params ) = @_;

   my $redaction_event_id;

   matrix_do_and_wait_for_sync( $user,
      do => sub {
         matrix_redact_event(
            $user, $room_id, $event_id, %params
         )->on_done( sub {
            ( $redaction_event_id ) = @_;
         });
      }, check => sub {
         my ( $sync_body ) = @_;
         return sync_timeline_contains(
            $sync_body, $room_id, sub {
               $_[0]->{event_id} eq $redaction_event_id
            },
         );
      },
   )->then( sub {
      return Future->done( $redaction_event_id );
   });
}

push @EXPORT, qw( matrix_redact_event_synced );

test "POST /rooms/:room_id/redact/:event_id as power user redacts message",
   requires => [ local_user_fixtures( 2 ),
                 qw( can_send_message )],

   do => sub {
      my ( $creator, $sender ) = @_;

      make_room_and_message( [ $creator, $sender ], $sender )
      ->then( sub {
         my ( $room_id, $to_redact ) = @_;

         $to_redact = uri_escape( $to_redact );

         do_request_json_for( $creator,
            method => "POST",
            uri    => "/r0/rooms/$room_id/redact/$to_redact",
            content => {},
         );
      });
   };

test "POST /rooms/:room_id/redact/:event_id as original message sender redacts message",
   requires => [ local_user_fixtures( 2 ),
                 qw( can_send_message )],

   do => sub {
      my ( $creator, $sender ) = @_;

      make_room_and_message( [ $creator, $sender ], $sender )
      ->then( sub {
         my ( $room_id, $to_redact ) = @_;

         $to_redact = uri_escape( $to_redact );

         do_request_json_for( $sender,
               method => "POST",
               uri    => "/r0/rooms/$room_id/redact/$to_redact",
               content => {},
         );
      });
   };

test "POST /rooms/:room_id/redact/:event_id as random user does not redact message",
   requires => [ local_user_fixtures( 3 ),
                 qw( can_send_message )],

   do => sub {
      my ( $creator, $sender, $redactor ) = @_;

      make_room_and_message( [ $creator, $sender, $redactor ], $sender )
      ->then( sub {
         my ( $room_id, $to_redact ) = @_;

         $to_redact = uri_escape( $to_redact );

         do_request_json_for( $redactor,
               method => "POST",
               uri    => "/r0/rooms/$room_id/redact/$to_redact",
               content => {},
         )->main::expect_http_403;
      });
   };

test "POST /redact disallows redaction of event in different room",
   requires => [ local_user_and_room_fixtures(), local_user_and_room_fixtures() ],

   do => sub {
      my ( $user1, $room1, $user2, $room2 ) = @_;

      matrix_send_room_text_message( $user1, $room1,
         body => "test"
      )->then( sub {
         my ( $event_id ) = @_;

         matrix_redact_event( $user2, $room2, $event_id )
      })->main::expect_http_400;
   };

test "Redaction of a redaction redacts the redaction reason",
   requires => [ local_user_fixtures( 2 ),
                 qw( can_send_message )],

   do => sub {
      my ( $creator, $sender ) = @_;

      my ( $room_id, $redaction_id );

      make_room_and_message( [ $creator, $sender ], $sender )
      ->then( sub {
         my $to_redact;
         ( $room_id, $to_redact ) = @_;

         matrix_redact_event_synced(
            $creator, $room_id, $to_redact,
            reason => "Offensively bad pun",
         );
      })->then( sub {
         ( $redaction_id ) = @_;

         # fetch the redaction and check the reason is in place
         do_request_json_for( $creator,
            method  => "GET",
            uri     => "/r0/rooms/$room_id/event/${ \uri_escape( $redaction_id ) }",
         );
      })->then( sub {
         my ( $event ) = @_;
         log_if_fail "Fetched redaction before metaredaction", $event;
         assert_eq( $event->{content}->{reason}, "Offensively bad pun", "content not in redaction");

         # now redact it
         matrix_redact_event_synced(
            $creator, $room_id, $redaction_id,
         );
      })->then( sub {
         # ... and refetch...

         do_request_json_for( $creator,
            method  => "GET",
            uri     => "/r0/rooms/$room_id/event/${ \uri_escape( $redaction_id ) }",
         );
      })->then( sub {
         my ( $event ) = @_;
         log_if_fail "Fetched redaction after metaredaction", $event;
         exists $event->{content}->{reason} and die "Redaction was not redacted";

         Future->done;
      });
   };
