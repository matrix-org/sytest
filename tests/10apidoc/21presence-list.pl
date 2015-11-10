# Eventually this will be changed; see SPEC-53
my $PRESENCE_LIST_URI = "/api/v1/presence/list/:user_id";

my $fixture = local_user_fixture();
my $friend_fixture = local_user_fixture();

test "GET /presence/:user_id/list initially empty",
   requires => [ $fixture ],

   check => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => $PRESENCE_LIST_URI,
      )->then( sub {
         my ( $body ) = @_;

         require_json_list( $body );
         @$body == 0 or die "Expected an empty list";

         Future->done(1);
      });
   };

test "POST /presence/:user_id/list can invite users",
   requires => [ $fixture, $friend_fixture ],

   provides => [qw( can_invite_presence )],

   do => sub {
      my ( $user, $friend ) = @_;

      do_request_json_for( $user,
         method => "POST",
         uri    => $PRESENCE_LIST_URI,

         content => {
            invite => [ $friend->user_id ],
         },
      );
   },

   check => sub {
      my ( $user, $friend ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => $PRESENCE_LIST_URI,
      )->then( sub {
         my ( $body ) = @_;

         require_json_nonempty_list( $body );

         require_json_keys( $body->[0], qw( accepted presence user_id ));
         $body->[0]->{user_id} eq $friend->user_id or
            die "Expected friend user_id";

         provide can_invite_presence => 1;

         Future->done(1);
      });
   };

test "POST /presence/:user_id/list can drop users",
   requires => [ $fixture,
                 qw( can_invite_presence )],

   provides => [qw( can_drop_presence )],

   do => sub {
      my ( $user ) = @_;

      # To be robust at this point, find out what friends we have and drop
      # them all
      do_request_json_for( $user,
         method => "GET",
         uri    => $PRESENCE_LIST_URI,
      )->then( sub {
         my ( $body ) = @_;

         my @friends = map { $_->{user_id} } @$body;

         do_request_json_for( $user,
            method => "POST",
            uri    => $PRESENCE_LIST_URI,

            content => {
               drop => \@friends,
            }
         )
      });
   },

   check => sub {
      my ( $user ) = @_;

      do_request_json_for( $user,
         method => "GET",
         uri    => $PRESENCE_LIST_URI,
      )->then( sub {
         my ( $body ) = @_;

         require_json_list( $body );
         @$body == 0 or die "Expected an empty list";

         provide can_drop_presence => 1;

         Future->done(1);
      });
   };
