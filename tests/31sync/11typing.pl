test "Typing events appear in initial sync",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id );

      my $filter = {
         room => {
            timeline  => { types => [] },
            state     => { types => [] },
            ephemeral => { types => [ "m.typing" ] },
         },
         presence => { types => [] },
      };

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

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
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_sync ) ],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id );

      my $filter = {
         room => {
            timeline  => { types => [] },
            state     => { types => [] },
            ephemeral => { types => [ "m.typing" ] },
         },
         presence => { types => [] },
      };

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         matrix_typing( $user, $room_id, typing => 1, timeout => 30000 );
      })->then( sub {
         matrix_sync_again( $user, filter => $filter_id );
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
   requires => [ local_user_fixture( with_events => 0 ), qw( can_sync )],

   check => sub {
      my ( $user ) = @_;

      my ( $filter_id, $room_id );

      my $filter = {
         room => {
            timeline  => { types => [] },
            state     => { types => [] },
            ephemeral => { types => [ "m.typing" ] },
         },
         presence => { types => [] },
      };

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         matrix_typing( $user, $room_id, typing => 1, timeout => 30000 );
      })->then( sub {
         Future->needs_all( map {
            matrix_send_room_message( $user, $room_id,
               content => { "filler" => $_ },
               type    => "a.made.up.filler.type",
            )
         } 0 .. 20 );
      })->then( sub {
         matrix_sync_again( $user, filter => $filter_id );
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
