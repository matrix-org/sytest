use Time::HiRes qw( time );

push our @EXPORT, qw( matrix_typing );

=head1 matrix_typing

   matrix_typing($user, $room_id, typing => 1, timeout => 30000)->get;

Mark the user as typing.

=cut

sub matrix_typing
{
   my ( $user, $room_id, %params ) = @_;

   do_request_json_for( $user,
      method => "PUT",
      uri    => "/r0/rooms/$room_id/typing/:user_id",
      content => \%params,
   );
}


my $typing_user_fixture = local_user_fixture( with_events => 1 );

my $local_user_fixture = local_user_fixture( with_events => 1 );

my $remote_user_fixture = remote_user_fixture( with_events => 1 );

my $room_fixture = magic_room_fixture(
   requires_users => [
      $typing_user_fixture, $local_user_fixture, $remote_user_fixture
   ],
);


test "Typing notification sent to local room members",
   requires => [ $typing_user_fixture, $local_user_fixture, $room_fixture,
                qw( can_set_room_typing )],

   do => sub {
      my ( $typinguser, $local_user, $room_id ) = @_;

      matrix_typing( $typinguser, $room_id,
         typing => JSON::true,
         timeout => 30000, # msec
      )->then( sub {
         Future->needs_all( map {
            my $recvuser = $_;

            await_sync_ephemeral_contains($recvuser, $room_id,
               check => sub {
                  my ( $event ) = @_;
                  return unless $event->{type} eq "m.typing";

                  assert_json_keys( $event, qw( type content ));
                  assert_json_keys( my $content = $event->{content}, qw( user_ids ));
                  assert_json_list( my $users = $content->{user_ids} );

                  scalar @$users == 1 or
                     die "Expected 1 member to be typing";
                  $users->[0] eq $typinguser->user_id or
                     die "Expected ${\ $typinguser->user_id } to be typing";

                  return 1;
               },
            )
         } $typinguser, $local_user );
      });
   };


test "Typing notifications also sent to remote room members",
   requires => [ $typing_user_fixture, $remote_user_fixture, $room_fixture,
                qw( can_set_room_typing can_join_remote_room_by_alias )],

   do => sub {
      my ( $typinguser, $remote_user, $room_id ) = @_;

      await_sync_ephemeral_contains($remote_user, $room_id,
         check => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.typing";

            assert_json_keys( $event, qw( type content ));
            assert_json_keys( my $content = $event->{content}, qw( user_ids ));

            assert_json_list( my $users = $content->{user_ids} );

            scalar @$users == 1 or
               die "Expected 1 member to be typing";
            $users->[0] eq $typinguser->user_id or
               die "Expected ${\ $typinguser->user_id } to be typing";

            return 1;
         },
      )
   };


test "Typing can be explicitly stopped",
   requires => [ $typing_user_fixture, $local_user_fixture, $room_fixture,
                qw( can_set_room_typing )],

   do => sub {
      my ( $typinguser, $local_user, $room_id ) = @_;

      matrix_typing( $typinguser, $room_id, typing => JSON::false )->then( sub {
         Future->needs_all( map {
            my $recvuser = $_;

            await_sync_ephemeral_contains($recvuser, $room_id,
               check => sub {
                  my ( $event ) = @_;
                  return unless $event->{type} eq "m.typing";

                  assert_json_keys( $event, qw( type content ));
                  assert_json_keys( my $content = $event->{content}, qw( user_ids ));
                  assert_json_list( my $users = $content->{user_ids} );

                  return scalar @$users == 0;
               },
            )
         } $typinguser, $local_user );
      });
   };
