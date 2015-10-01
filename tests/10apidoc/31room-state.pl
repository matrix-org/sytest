use List::UtilsBy qw( partition_by );

my $name = "room name here";

test "POST /rooms/:room_id/state/m.room.name sets name",
   requires => [qw( user room_id
                    can_room_initial_sync )],

   provides => [qw( can_set_room_name )],

   do => sub {
      my ( $user, $room_id ) = @_;

      do_request_json_for( $user,
         method => "PUT",
         uri    => "/api/v1/rooms/$room_id/state/m.room.name",

         content => { name => $name },
      );
   },

   check => sub {
      my ( $user, $room_id ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/rooms/$room_id/initialSync",
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( state ));
         my $state = $body->{state};

         my %state_by_type = partition_by { $_->{type} } @$state;

         $state_by_type{"m.room.name"} or
            die "Expected to find m.room.name state";

         provide can_set_room_name => 1;

         Future->done(1);
      });
   };

test "GET /rooms/:room_id/state/m.room.name gets name",
   requires => [qw( user room_id
                    can_set_room_name )],

   provides => [qw( can_get_room_name )],

   check => sub {
      my ( $user, $room_id ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/rooms/$room_id/state/m.room.name",
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( name ));

         $body->{name} eq $name or
            die "Expected name to be '$name'";

         provide can_get_room_name => 1;

         Future->done(1);
      });
   };

my $topic = "A new topic for the room";

test "POST /rooms/:room_id/state/m.room.topic sets topic",
   requires => [qw( user room_id
                    can_room_initial_sync )],

   provides => [qw( can_set_room_topic )],

   do => sub {
      my ( $user, $room_id ) = @_;

      do_request_json_for( $user,
         method => "PUT",
         uri    => "/api/v1/rooms/$room_id/state/m.room.topic",

         content => { topic => $topic },
      );
   },

   check => sub {
      my ( $user, $room_id ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/rooms/$room_id/initialSync",
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( state ));
         my $state = $body->{state};

         my %state_by_type = partition_by { $_->{type} } @$state;

         $state_by_type{"m.room.topic"} or
            die "Expected to find m.room.topic state";

         provide can_set_room_topic => 1;

         Future->done(1);
      });
   };

test "GET /rooms/:room_id/state/m.room.topic gets topic",
   requires => [qw( user room_id
                    can_set_room_topic )],

   provides => [qw( can_get_room_topic )],

   check => sub {
      my ( $user, $room_id ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/rooms/$room_id/state/m.room.topic",
      )->then( sub {
         my ( $body ) = @_;

         require_json_keys( $body, qw( topic ));

         $body->{topic} eq $topic or
            die "Expected topic to be '$topic'";

         provide can_get_room_topic => 1;

         Future->done(1);
      });
   };

test "GET /rooms/:room_id/state fetches entire room state",
   requires => [qw( user room_id )],

   provides => [qw( can_get_room_all_state )],

   check => sub {
      my ( $user, $room_id ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => "/api/v1/rooms/$room_id/state",
      )->then( sub {
         my ( $body ) = @_;

         require_json_list( $body );

         my %state_by_type = partition_by { $_->{type} } @$body;

         defined $state_by_type{$_} or die "Missing $_ state" for
            qw( m.room.create m.room.join_rules m.room.name m.room.power_levels );

         provide can_get_room_all_state => 1;

         Future->done(1);
      });
   };

push our @EXPORT, qw( matrix_get_room_state );

sub matrix_get_room_state
{
   my ( $user, $room_id, %opts ) = @_;

   defined $opts{state_key} and not defined $opts{type} and
      croak "Cannot matrix_get_room_state() with a state_key but no type";

   do_request_json_for( $user,
      method => "GET",
      uri    => join( "/",
         "/api/v1/rooms/$room_id/state", grep { defined } $opts{type}, $opts{state_key}
      ),
   );
}
