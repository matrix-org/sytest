push our @EXPORT, qw( matrix_add_tag );

=head2 matrix_add_tag

   matrix_add_tag($user, $room_id, $tag)->get;

Add a tag to the room for the user.

=cut

sub matrix_add_tag
{
   my ( $user, $room_id, $tag, $content ) = @_;

   do_request_json_for( $user,
      method  => "PUT",
      uri     => "/v2_alpha/user/:user_id/rooms/$room_id/tags/$tag",
      content => $content
   );
}


=head2 matrix_remove_tag

    matrix_remove_tag( $user, $room_id, $tag )->get;

Remove a tag from the room for the user.

=cut

sub matrix_remove_tag
{
   my ( $user, $room_id, $tag ) = @_;

   do_request_json_for( $user,
      method  => "DELETE",
      uri     => "/v2_alpha/user/:user_id/rooms/$room_id/tags/$tag",
      content => {}
   );
}


=head2 matrix_list_tags

    my $tags = matrix_list_tags( $user, $room_id )->get;

List the tags on the room for the user.

=cut

sub matrix_list_tags
{
   my ( $user, $room_id, $content) = @_;

   do_request_json_for( $user,
      method  => "GET",
      uri     => "/v2_alpha/user/:user_id/rooms/$room_id/tags",
   )->then( sub {
      my ( $body ) = @_;

      assert_json_keys( $body, qw( tags ) );

      Future->done( $body->{tags} );
   });
}


test "Can add tag",
   requires => [ local_user_fixture( with_events => 0 ) ],

   proves => [qw( can_add_tag )],

   do => sub {
      my ( $user ) = @_;

      matrix_create_room( $user )->then( sub {
         my ( $room_id ) = @_;

         matrix_add_tag( $user, $room_id, "test_tag", {} );
      });
   };


test "Can remove tag",
   requires => [ local_user_fixture( with_events => 0 ) ],

   proves => [qw( can_remove_tag )],

   do => sub {
      my ( $user ) = @_;

      matrix_create_room( $user )->then( sub {
         my ( $room_id ) = @_;

         matrix_remove_tag( $user, $room_id, "test_tag" );
      });
   };


test "Can list tags for a room",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_add_tag can_remove_tag )],

   do => sub {
      my ( $user ) = @_;

      my $room_id;

      matrix_create_room( $user )->then( sub {
         ( $room_id ) = @_;

         matrix_add_tag( $user, $room_id, "test_tag", {} );
      })->then( sub {
         matrix_list_tags( $user, $room_id );
      })->then( sub {
         my ( $tags ) = @_;

         log_if_fail "Tags after add", $tags;

         keys %{ $tags } == 1 or die "Expected one tag for the room";
         defined $tags->{test_tag} or die "Unexpected tag";

         matrix_remove_tag( $user, $room_id, "test_tag" );
      })->then( sub {
         matrix_list_tags( $user, $room_id );
      })->then( sub {
         my ( $tags ) = @_;

         log_if_fail "Tags after delete", $tags;

         keys %{ $tags } == 0 or die "Expected no tags for the room";

         Future->done(1);
      });
   };


=head2 create_room_and_add_tag

   my ( $room_id ) = create_room_and_add_tag( $user )->get;

Creates a room and add a tag called "test_tag" for that user to the room with
a tag content of {"order": 1}.

=cut

sub create_room_and_add_tag
{
   my ( $user ) = @_;

   matrix_create_room( $user )->then( sub {
      my ( $room_id ) = @_;

      matrix_add_tag( $user, $room_id, "test_tag", { order => 1 } )
         ->then_done( $room_id );
   });
}


=head2 check_tag_event

   check_tag_event( $event, %args );

Checks that a room tag event has the correct content (or is empty, if the
C<expect_empty> named arg true)

=cut

sub check_tag_event {
   my ( $event, %args ) = @_;

   log_if_fail "Tag event", $event;

   my %tags = %{ $event->{content}{tags} };

   if( $args{expect_empty} ) {
      keys %tags == 0 or die "Expected empty tag"
   }
   else {
      keys %tags == 1 or die "Expected exactly one tag";
      defined $tags{test_tag} or die "Unexpected tag";
      $tags{test_tag}{order} == 1 or die "Expected order == 1";
   }
}


test "Tags appear in the v1 /events stream",
   requires => [ local_user_fixture( with_events => 1 ),
                 qw( can_add_tag can_remove_tag ) ],

   do => sub {
      my ( $user ) = @_;

      create_room_and_add_tag( $user )->then( sub {
         my ( $room_id ) = @_;

         await_event_for( $user, filter => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.tag"
               and $event->{room_id} eq $room_id;

            check_tag_event( $event );

            return 1;
         });
      });
   };


=head2 check_account_data

   check_account_data( $event, %args );

Checks that the account_data section has a tag event
and that the tag event has the correct content.  If the C<expect_empty>
named argument is set then the 'correct' content is an empty tag.

=cut

sub check_account_data {
   my ( $account_data, %args ) = @_;

   log_if_fail "Private User Data:", $account_data;

   my $tag_event = $account_data->[0];
   $tag_event->{type} eq "m.tag" or die "Expected a m.tag event";
   not defined $tag_event->{room_id} or die "Unxpected room_id";

   check_tag_event( $tag_event, %args );
}


test "Tags appear in the v1 /initalSync",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_add_tag can_remove_tag ) ],

   do => sub {
      my ( $user ) = @_;

      my $room_id;

      create_room_and_add_tag( $user )->then( sub {
         ( $room_id ) = @_;

         matrix_initialsync( $user );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}[0];
         assert_json_keys( $room, qw( account_data ) );

         # TODO(paul): Surely assert that the $room found is indeed $room_id ?

         check_account_data( $room->{account_data} );

         Future->done( 1 );
      });
   };


test "Tags appear in the v1 room initial sync",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_add_tag can_remove_tag )],

   do => sub {
      my ( $user ) = @_;

      my $room_id;

      create_room_and_add_tag( $user )->then( sub {
         ( $room_id ) = @_;

         matrix_initialsync_room( $user, $room_id );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body;
         assert_json_keys( $room, qw( account_data ) );

         # TODO(paul): Surely assert that the $room found is indeed $room_id ?

         check_account_data( $room->{account_data} );

         Future->done( 1 );
      });
   };


test "Tags appear in an initial v2 /sync",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_add_tag can_remove_tag can_sync ) ],

   do => sub {
      my ( $user ) = @_;

      my ( $room_id, $filter_id );

      my $filter = {};

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_add_tag( $user, $room_id, "test_tag", { order => 1 } );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};
         assert_json_keys( $room, qw( account_data ) );

         check_account_data( $room->{account_data}{events} );

         Future->done( 1 );
      });
   };


test "Newly updated tags appear in an incremental v2 /sync",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_add_tag can_remove_tag can_sync ) ],

   do => sub {
      my ( $user ) = @_;

      my ( $room_id, $filter_id );

      my $filter = {};

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user, $filter => $filter_id );
      })->then( sub {
         matrix_add_tag( $user, $room_id, "test_tag", { order => 1 } );
      })->then( sub {
         matrix_sync_again( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};
         assert_json_keys( $room, qw( account_data ) );

         check_account_data( $room->{account_data}{events} );

         Future->done( 1 );
      });
   };

test "Deleted tags appear in an incremental v2 /sync",
   requires => [ local_user_fixture( with_events => 0 ),
                 qw( can_add_tag can_remove_tag can_sync ) ],

   do => sub {
      my ( $user ) = @_;

      my ( $room_id, $filter_id );

      my $filter = {};

      matrix_create_filter( $user, $filter )->then( sub {
         ( $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user, $filter => $filter_id );
      })->then( sub {
         matrix_add_tag( $user, $room_id, "test_tag", { order => 1 } );
      })->then( sub {
         matrix_sync_again( $user, filter => $filter_id );
      })->then( sub {
         matrix_remove_tag( $user, $room_id, "test_tag" );
      })->then( sub {
         matrix_sync_again( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{join}{$room_id};
         assert_json_keys( $room, qw( account_data ) );

         check_account_data( $room->{account_data}{events},
            expect_empty => 1,
         );

         Future->done( 1 );
      });
   };
