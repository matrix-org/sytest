prepare "More room members",
   requires => [qw( do_request_json_for flush_events_for more_users room_id
                    can_join_room_by_id )],

   do => sub {
      my ( $do_request_json_for, $flush_events_for, $more_users, $room_id ) = @_;

      Future->needs_all( map {
         my $user = $_;

         $flush_events_for->( $user )->then( sub {
            $do_request_json_for->( $user,
               method => "POST",
               uri    => "/rooms/$room_id/join",

               content => {},
            );
         });
      } @$more_users );
   };

test "New room members see their own join event",
   requires => [qw( GET_new_events_for more_users room_id
                    can_join_room_by_id )],

   check => sub {
      my ( $GET_new_events_for, $more_users, $room_id ) = @_;

      Future->needs_all( map {
         my $user = $_;

         $GET_new_events_for->( $user, "m.room.member",
            timeout => 50,
         )->then( sub {
            my $found;
            foreach my $event ( @_ ) {
               json_keys_ok( $event, qw( type room_id user_id membership ));
               next unless $event->{room_id} eq $room_id;
               next unless $event->{user_id} eq $user->user_id;

               $found++;

               $event->{membership} eq "join" or
                  die "Expected user membership as 'join'";
            }

            $found or
               die "Failed to find an appropriate m.room.member event";

            Future->done(1);
         });
      } @$more_users );
   };
