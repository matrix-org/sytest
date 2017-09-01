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


my $typing_user_fixture = local_user_fixture();

my $local_user_fixture = local_user_fixture();

my $remote_user_fixture = remote_user_fixture();

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
         typing => 1,
         timeout => 30000, # msec
      )->then( sub {
         Future->needs_all( map {
            my $recvuser = $_;

            await_event_for( $recvuser, filter => sub {
               my ( $event ) = @_;

               return unless $event->{type} eq "m.typing";

               assert_json_keys( $event, qw( type room_id content ));
               assert_json_keys( my $content = $event->{content}, qw( user_ids ));

               return unless $event->{room_id} eq $room_id;

               assert_json_list( my $users = $content->{user_ids} );

               scalar @$users == 1 or
                  die "Expected 1 member to be typing";
               $users->[0] eq $typinguser->user_id or
                  die "Expected ${\ $typinguser->user_id } to be typing";

               return 1;
            })
         } $typinguser, $local_user );
      });
   };


test "Typing notifications also sent to remote room members",
   requires => [ $typing_user_fixture, $remote_user_fixture, $room_fixture,
                qw( can_set_room_typing can_join_remote_room_by_alias )],

   do => sub {
      my ( $typinguser, $remote_user, $room_id ) = @_;

      await_event_for( $remote_user, filter => sub {
         my ( $event ) = @_;

         return unless $event->{type} eq "m.typing";

         assert_json_keys( $event, qw( type room_id content ));
         assert_json_keys( my $content = $event->{content}, qw( user_ids ));

         return unless $event->{room_id} eq $room_id;

         assert_json_list( my $users = $content->{user_ids} );

         scalar @$users == 1 or
            die "Expected 1 member to be typing";
         $users->[0] eq $typinguser->user_id or
            die "Expected ${\ $typinguser->user_id } to be typing";

         return 1;
      })
   };


test "Typing can be explicitly stopped",
   requires => [ $typing_user_fixture, $local_user_fixture, $room_fixture,
                qw( can_set_room_typing )],

   do => sub {
      my ( $typinguser, $local_user, $room_id ) = @_;

      matrix_typing( $typinguser, $room_id, typing => 0 )->then( sub {
         Future->needs_all( map {
            my $recvuser = $_;

            await_event_for( $recvuser, filter => sub {
               my ( $event ) = @_;

               return unless $event->{type} eq "m.typing";

               assert_json_keys( $event, qw( type room_id content ));
               assert_json_keys( my $content = $event->{content}, qw( user_ids ));

               return unless $event->{room_id} eq $room_id;

               assert_json_list( my $users = $content->{user_ids} );

               scalar @$users and
                  die "Expected 0 members to be typing";

               return 1;
            })
         } $typinguser, $local_user );
      });
   };


multi_test "Typing notifications timeout and can be resent",
   requires => [ $typing_user_fixture, $room_fixture,
                qw( can_set_room_typing )],

   timeout => 100,

   bug => "DISABLED",

   do => sub {
      my ( $user, $room_id ) = @_;

      die "This test has been disabled due to synapse no longer supporting small typing timeouts.";

      my $start_time = time();

      flush_events_for( $user )->then( sub {
         matrix_typing( $user, $room_id,
            typing => 1,
            timeout => 10000, # msec; i.e. very long
         );
      })->then( sub {
         pass( "Sent typing notification" );

         # start typing
         await_event_for( $user, filter => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.typing";
            return unless $event->{room_id} eq $room_id;

            return unless scalar @{ $event->{content}{user_ids} };

            pass( "Received start notification" );
            return 1;
         });
      })->then( sub {
         matrix_typing( $user, $room_id,
            typing => 1,
            timeout => 100, # msec; i.e. very short
         );
      })->then( sub {
         # stop typing
         await_event_for( $user, filter => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.typing";
            return unless $event->{room_id} eq $room_id;

            return if scalar @{ $event->{content}{user_ids} };

            ( time() - $start_time ) < 0.5 or
               die "Took too long to time out";

            pass( "Received stop notification" );
            return 1;
         });
      })->then( sub {
         matrix_typing( $user, $room_id,
            typing => 1,
            timeout => 10000,
         );
      })->then( sub {
         pass( "Sent second notification" );

         Future->done(1);
      });
   };
