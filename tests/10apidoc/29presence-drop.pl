# Eventually this will be changed; see SPEC-53
my $PRESENCE_LIST_URI = "/api/v1/presence/list/:user_id";

# This test is at 29, just before we start doing things with rooms. We'll clear
# out the presence list here so as to ensure any presence-based messaging that
# happens now only happens because of presence in rooms.

test "POST /presence/:user_id/list can drop users",
   requires => [qw( user can_invite_presence )],

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
