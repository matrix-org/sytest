push our @EXPORT, qw(
   matrix_add_account_data matrix_add_room_account_data
   matrix_add_filler_account_data_synced
);

=head2 matrix_add_account_data

   matrix_add_account_data( $user, $type, $content )->get;

Add account data for the user.

=cut

sub matrix_add_account_data
{
   my ( $user, $type, $content ) = @_;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/r0/user/:user_id/account_data/$type",
      content => $content
   );
}

=head2 matrix_add_room_account_data

    matrix_add_account_data( $user, $room_id, $type, $content )->get;

Add account data for the user for a room.

=cut

sub matrix_add_room_account_data
{
   my ( $user, $room_id, $type, $content ) = @_;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/r0/user/:user_id/rooms/$room_id/account_data/$type",
      content => $content
   );
}

=head2 matrix_get_account_data

   matrix_get_account_data( $user, $type, $content )->get;

Get account data for the user.

=cut

sub matrix_get_account_data
{
   my ( $user, $type ) = @_;

   do_request_json_for( $user,
      method  => "GET",
      uri     => "/r0/user/:user_id/account_data/$type",
   );
}

=head2 matrix_get_room_account_data

    matrix_get_account_data( $user, $room_id, $type, $content )->get;

Get account data for the user for a room.

=cut

sub matrix_get_room_account_data
{
   my ( $user, $room_id, $type, $content ) = @_;

   do_request_json_for( $user,
      method  => "GET",
      uri     => "/r0/user/:user_id/rooms/$room_id/account_data/$type",
   );
}

sub matrix_add_filler_account_data_synced
{
   my ( $user ) = @_;

   my $random_id = join "", map { chr 64 + rand 63 } 1 .. 20;
   my $type = "a.made.up.filler.type";

   matrix_do_and_wait_for_sync( $user,
      do => sub {
         matrix_add_account_data( $user, $type, {
            "id" => $random_id,
         } );
      },
      check => sub {
         my ( $sync_body ) = @_;

         my $global_account_data =  $sync_body->{account_data}{events};

         return any {
            $_->{type} eq $type && $_->{content}{id} eq $random_id
         } @{ $global_account_data };
      },
   );
}
