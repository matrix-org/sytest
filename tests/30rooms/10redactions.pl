test "POST /rooms/:room_id/redact/:event_id as power user redacts message",
   requires => [qw( do_request_json_for make_test_room local_users )],

   do => sub {
      my ( $do_request_json_for, $make_test_room, $local_users ) = @_;
      # 100 power level
      my $room_creator   = $local_users->[0];
      # 0 power level
      my $test_user = $local_users->[1];

      make_post($do_request_json_for, $make_test_room, $local_users, $test_user)->then(sub {
         my ( $room_id, $to_redact ) = @_;

         $do_request_json_for->( $room_creator,
               method => "POST",
               uri    => "/rooms/$room_id/redact/$to_redact",
               content => {},
         )->then( sub {
            Future->done(1);
         });
      });
   };

test "POST /rooms/:room_id/redact/:event_id as original message sender redacts message",
   requires => [qw( do_request_json_for make_test_room local_users )],

   do => sub {
      my ( $do_request_json_for, $make_test_room, $local_users ) = @_;
      # 0 power level
      my $test_user = $local_users->[1];

      make_post($do_request_json_for, $make_test_room, $local_users, $test_user)->then(sub {
         my ( $room_id, $to_redact ) = @_;

         $do_request_json_for->( $test_user,
               method => "POST",
               uri    => "/rooms/$room_id/redact/$to_redact",
               content => {},
         )->then( sub {
            Future->done(1);
         });
      });
   };

test "POST /rooms/:room_id/redact/:event_id as random user does not redact message",
   requires => [qw( do_request_json_for make_test_room local_users )],

   do => sub {
      my ( $do_request_json_for, $make_test_room, $local_users ) = @_;
      # Both have 0 power level
      my $test_user = $local_users->[1];
      my $other_test_user = $local_users->[2];

      make_post($do_request_json_for, $make_test_room, $local_users, $test_user)->then(sub {
         my ( $room_id, $to_redact ) = @_;

         $do_request_json_for->( $other_test_user,
               method => "POST",
               uri    => "/rooms/$room_id/redact/$to_redact",
               content => {},
         )->then( sub {
            Future->fail( "Expected not to succeed in redacting message" );
         }, sub {
            my ( $failure, $name, @args ) = @_;

            defined $name and $name eq "http" or
               die "Expected failure kind to be 'http'";

            my ( $resp, $req ) = @args;

            $resp->code == 403 or
               die "Expected HTTP response code to be 403 but was ${\$resp->code}";

            Future->done(1);
         });
      });
   };

sub make_post
{
   my ( $do_request_json_for, $make_test_room, $users, $sender ) = @_;

   my $room_id;
   $make_test_room->( @$users )->on_done( sub {
      ( $room_id ) = @_;
   })->then( sub {
      $do_request_json_for->( $sender,
         method => "POST",
         uri    => "/rooms/$room_id/send/m.room.message",

         content => { msgtype => "m.message", body => "orangutans are not monkeys" },
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( event_id ));
         require_json_nonempty_string( $body->{event_id} );
         return Future->done( $room_id, $body->{event_id} );
      });
   });

};
