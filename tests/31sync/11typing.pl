test "Typing events appear in initial sync",
   requires => [qw( first_api_client can_sync )],

   check => sub {
      my ( $http ) = @_;

      my ( $user, $filter_id, $room_id );

      my $filter = {
         room => {
            timeline  => { types => [] },
            state     => { types => [] },
            ephemeral => { types => [ "m.typing" ] },
         },
         presence => { types => [] },
      };

      matrix_register_user_with_filter( $http, $filter )->then( sub {
         ( $user, $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_typing( $user, $room_id, typing => 1, timeout => 30000 );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};

         @{ $room->{ephemeral}{events} } == 1
            or die "Expected one typing event";

         my $typing = $room->{ephemeral}{events}[0];

         $typing->{type} eq "m.typing" or die "Expected a typing event";
         ( not defined $typing->{room_id} ) or die "Did not expect a room_id";
         @{ $typing->{content}{user_ids} } == 1
            or die "Expected one user to be typing";
         $typing->{content}{user_ids}[0] eq $user->user_id
            or die "Expected this user to be typing";

         Future->done(1);
      });
   };


test "Typing events appear in incremental sync",
   requires => [qw( first_api_client can_sync )],

   check => sub {
      my ( $http ) = @_;

      my ( $user, $filter_id, $room_id, $next );

      my $filter = {
         room => {
            timeline  => { types => [] },
            state     => { types => [] },
            ephemeral => { types => [ "m.typing" ] },
         },
         presence => { types => [] },
      };

      matrix_register_user_with_filter( $http, $filter )->then( sub {
         ( $user, $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         $next = $body->{next_batch};

         matrix_typing( $user, $room_id, typing => 1, timeout => 30000 );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id, since => $next );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};

         @{ $room->{ephemeral}{events} } == 1
            or die "Expected one typing event";

         my $typing = $room->{ephemeral}{events}[0];

         $typing->{type} eq "m.typing" or die "Expected a typing event";
         ( not defined $typing->{room_id} ) or die "Did not expect a room_id";
         @{ $typing->{content}{user_ids} } == 1
            or die "Expected one user to be typing";
         $typing->{content}{user_ids}[0] eq $user->user_id
            or die "Expected this user to be typing";

         Future->done(1);
      });
   };


test "Typing events appear in gapped sync",
   requires => [qw( first_api_client can_sync )],

   check => sub {
      my ( $http ) = @_;

      my ( $user, $filter_id, $room_id, $next );

      my $filter = {
         room => {
            timeline  => { types => [] },
            state     => { types => [] },
            ephemeral => { types => [ "m.typing" ] },
         },
         presence => { types => [] },
      };

      matrix_register_user_with_filter( $http, $filter )->then( sub {
         ( $user, $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         $next = $body->{next_batch};

         matrix_typing( $user, $room_id, typing => 1, timeout => 30000 );
      })->then( sub {
         Future->needs_all( map {
            matrix_send_room_message( $user, $room_id,
               content => { "filler" => $_ },
               type    => "a.made.up.filler.type",
            )
         } 0 .. 20 );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id, since => $next );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};

         @{ $room->{ephemeral}{events} } == 1
            or die "Expected one typing event";

         my $typing = $room->{ephemeral}{events}[0];

         $typing->{type} eq "m.typing" or die "Expected a typing event";
         ( not defined $typing->{room_id} ) or die "Did not expect a room_id";
         @{ $typing->{content}{user_ids} } == 1
            or die "Expected one user to be typing";
         $typing->{content}{user_ids}[0] eq $user->user_id
            or die "Expected this user to be typing";

         Future->done(1);
      });
   };
