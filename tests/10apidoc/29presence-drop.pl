# Eventually this will be changed; see SPEC-53
my $PRESENCE_LIST_URI = "/presence/list/:user_id";

# This test is at 29, just before we start doing things with rooms. We'll clear
# out the presence list here so as to ensure any presence-based messaging that
# happens now only happens because of presence in rooms.

test "POST /presence/:user_id/list can drop users",
   requires => [qw( do_request_json_authed can_invite_presence )],

   do => sub {
      my ( $do_request_json_authed ) = @_;

      # To be robust at this point, find out what friends we have and drop
      # them all
      $do_request_json_authed->(
         method => "GET",
         uri    => $PRESENCE_LIST_URI,
      )->then( sub {
         my ( $body ) = @_;

         my @friends = map { $_->{user_id} } @$body;

         $do_request_json_authed->(
            method => "POST",
            uri    => $PRESENCE_LIST_URI,

            content => {
               drop => \@friends,
            }
         )
      });
   },

   check => sub {
      my ( $do_request_json_authed ) = @_;

      $do_request_json_authed->(
         method => "GET",
         uri    => $PRESENCE_LIST_URI,
      )->then( sub {
         my ( $body ) = @_;

         json_list_ok( $body );
         @$body == 0 or die "Expected an empty list";

         Future->done(1);
      });
   };
