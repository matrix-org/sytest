my $fixture = local_user_fixture();

push our @EXPORT, qw( matrix_get_presence_status matrix_set_presence_status );

=head2 matrix_get_presence_status

   $status = matrix_get_presence_status( $user )

Returns a HASH reference containing the user's presence status. This will
contain a C<presence> field, and optionally a C<status_msg> field as well if
the user has one set.

=cut

sub matrix_get_presence_status
{
   my ( $user ) = @_;

   do_request_json_for( $user,
      method => "GET",
      uri    => "/r0/presence/:user_id/status",
   );
}

=head2 matrix_set_presence_status

   matrix_set_presence_status( $user, $presence, %params )

Sets the presence status of the given C<$user> to C<$presence>, with optional
additional parameters (such as C<status_msg>) given in C<%params>.

=cut

sub matrix_set_presence_status
{
   my ( $user, $presence, %params ) = @_;

   do_request_json_for( $user,
      method => "PUT",
      uri    => "/r0/presence/:user_id/status",

      content => { presence => $presence, %params }
   )->then_done();
}

test "GET /presence/:user_id/status fetches initial status",
   requires => [ $fixture ],

   check => sub {
      my ( $user ) = @_;

      matrix_get_presence_status( $user )->then( sub {
         my ( $body ) = @_;

         assert_json_keys( $body, qw( presence ));

         # TODO(paul): Newly-registered users might not yet have a
         #   last_active_ago
         # assert_json_number( $body->{last_active_ago} );
         # $body->{last_active_ago} >= 0 or
         #    die "Expected last_active_ago non-negative";

         Future->done(1);
      });
   };

my $status_msg = "Testing something";

test "PUT /presence/:user_id/status updates my presence",
   requires => [ $fixture ],

   proves => [qw( can_set_presence )],

   do => sub {
      my ( $user ) = @_;

      matrix_set_presence_status( $user, "online",
         status_msg => $status_msg,
      )
   },

   check => sub {
      my ( $user ) = @_;

      matrix_get_presence_status( $user )->then( sub {
         my ( $body ) = @_;

         ( $body->{status_msg} // "" ) eq $status_msg or
            die "Incorrect status_msg";

         Future->done(1);
      });
   };
