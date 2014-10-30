prepare "More room members",
   requires => [qw( do_request_json_for more_users room_id
                    can_join_room_by_id )],

   do => sub {
      my ( $do_request_json_for, $more_users, $room_id ) = @_;

      Future->needs_all( map {
         my $user = $_;

         $do_request_json_for->( $user,
            method => "POST",
            uri    => "/rooms/$room_id/join",

            content => {},
         );
      } @$more_users );
   };
