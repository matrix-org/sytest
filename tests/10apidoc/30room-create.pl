test "POST /createRoom makes a public room",
   requires => [qw( user can_initial_sync )],

   critical => 1,

   do => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "POST",
         uri    => "/api/v1/createRoom",

         content => {
            visibility      => "public",
            # This is just the localpart
            room_alias_name => "30room-create",
         },
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( room_id room_alias ));
         require_json_nonempty_string( $body->{room_id} );
         require_json_nonempty_string( $body->{room_alias} );

         Future->done(1);
      });
   },

   check => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/initialSync",
      )->then( sub {
         my ( $body ) = @_;

         require_json_list( $body->{rooms} );
         Future->done( scalar @{ $body->{rooms} } > 0 );
      });
   };

test "POST /createRoom makes a private room",
   requires => [qw( user )],

   provides => [qw( can_create_private_room )],

   do => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "POST",
         uri    => "/api/v1/createRoom",

         content => {
            visibility => "private",
         },
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( room_id ));
         require_json_nonempty_string( $body->{room_id} );

         provide can_create_private_room => 1;

         Future->done(1);
      });
   };

test "POST /createRoom makes a private room with invites",
   requires => [qw( user more_users
                    can_create_private_room )],

   provides => [qw( can_create_private_room_with_invite )],

   do => sub {
      my ( $user, $more_users ) = @_;
      my $invitee = $more_users->[0];

      do_request_json_for( $user,
         method => "POST",
         uri    => "/api/v1/createRoom",

         content => {
            visibility => "private",
            # TODO: This doesn't actually appear in the API docs yet
            invite     => [ $invitee->user_id ],
         },
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( room_id ));
         require_json_nonempty_string( $body->{room_id} );

         provide can_create_private_room_with_invite => 1;

         Future->done(1);
      });
   };

push our @EXPORT, qw( matrix_create_room );

sub matrix_create_room
{
   my ( $user, %opts ) = @_;
   is_User( $user ) or croak "Expected a User; got $user";

   do_request_json_for( $user,
      method => "POST",
      uri    => "/api/v1/createRoom",

      content => {
         visibility => $opts{visibility} || "public",
         ( defined $opts{room_alias_name} ?
            ( room_alias_name => $opts{room_alias_name} ) : () ),
         ( defined $opts{invite} ?
            ( invite => $opts{invite} ) : () ),
      }
   )->then( sub {
      my ( $body ) = @_;

      Future->done( $body->{room_id}, $body->{room_alias} );
   });
}
