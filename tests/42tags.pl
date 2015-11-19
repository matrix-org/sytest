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

      require_json_keys( $body, qw( tags ) );

      Future->done( $body->{tags} );
   });
}


test "Can add tag",
   requires => [qw( first_api_client )],

   provides => [qw( can_add_tag )],

   do => sub {
      my ( $http ) = @_;

      my ( $user, $room_id );

      matrix_register_user( $http, undef, with_events => 0 )->then( sub {
         ( $user ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_add_tag( $user, $room_id, "test_tag", {} );
      })->on_done( sub {
         provide can_add_tag => 1
      });
   };


test "Can remove tag",
   requires => [qw( first_api_client )],

   provides => [qw( can_remove_tag )],

   do => sub {
      my ( $http ) = @_;

      my ( $user, $room_id );

      matrix_register_user( $http, undef, with_events => 0 )->then( sub {
         ( $user ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_remove_tag( $user, $room_id, "test_tag" );
      })->on_done( sub {
         provide can_remove_tag => 1
      });
   };


test "Can list tags for a room",
   requires => [qw( first_api_client can_add_tag can_remove_tag )],

   do => sub {
      my ( $http ) = @_;

      my ( $user, $room_id );

      matrix_register_user( $http, undef, with_events => 0 )->then( sub {
         ( $user ) = @_;

         matrix_create_room( $user );
      })->then( sub {
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


=head2 register_user_and_create_room_and_add_tag

   my ( $user, $room_id ) = register_user_and_create_room_and_add_tag( $http,
      with_events => 0
   )->get;

Register a new user, create a room and add a tag called "test_tag" for that
user to the room with a tag content of {"order": 1}.

=cut

sub register_user_and_create_room_and_add_tag
{
   my ( $http, %params ) = @_;

   my ( $user, $room_id );

   matrix_register_user( $http, undef, %params )->then( sub {
      ( $user ) = @_;
         matrix_create_room( $user );
   })->then( sub {
      ( $room_id ) = @_;

      matrix_add_tag( $user, $room_id, "test_tag", { order => 1 } );
   })->then( sub {
      Future->done( $user, $room_id );
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
   requires => [qw( first_api_client can_add_tag can_remove_tag )],

   do => sub {
      my ( $http ) = @_;

      my ( $user, $room_id );

      register_user_and_create_room_and_add_tag( $http,
         with_events => 1
      )->then( sub {
         ( $user, $room_id ) = @_;

         await_event_for( $user, filter => sub {
            my ( $event ) = @_;
            return unless $event->{type} eq "m.tag"
               and $event->{room_id} eq $room_id;

            check_tag_event( $event );

            return 1;
         });
      });
   };


=head2 check_private_user_data

   check_private_user_data( $event, %args );

Checks that the private_user_data section has a tag event
and that the tag event has the correct content.  If the C<expect_empty>
named argument is set then the 'correct' content is an empty tag.

=cut

sub check_private_user_data {
   my ( $private_user_data, %args ) = @_;

   log_if_fail "Private User Data:", $private_user_data;

   my $tag_event = $private_user_data->[0];
   $tag_event->{type} eq "m.tag" or die "Expected a m.tag event";
   not defined $tag_event->{room_id} or die "Unxpected room_id";

   check_tag_event( $tag_event, %args );
}


test "Tags appear in the v1 /initalSync",
   requires => [qw( first_api_client can_add_tag can_remove_tag )],

   do => sub {
      my ( $http ) = @_;

      my ( $user, $room_id );

      register_user_and_create_room_and_add_tag( $http,
         with_events => 0
      )->then( sub {
         ( $user, $room_id ) = @_;

         matrix_initialsync( $user );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}[0];
         require_json_keys( $room, qw( private_user_data ) );

         check_private_user_data( $room->{private_user_data} );

         Future->done( 1 );
      });
   };


test "Tags appear in the v1 room initial sync",
   requires => [qw( first_api_client can_add_tag can_remove_tag )],

   do => sub {
      my ( $http ) = @_;

      my ( $user, $room_id );
      register_user_and_create_room_and_add_tag( $http,
         with_events => 0
      )->then( sub {
         ( $user, $room_id ) = @_;

         matrix_initialsync_room( $user, $room_id );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body;
         require_json_keys( $room, qw( private_user_data ) );

         check_private_user_data( $room->{private_user_data} );

         Future->done( 1 );
      });
   };


test "Tags appear in an initial v2 /sync",
   requires => [qw( first_api_client can_add_tag can_remove_tag can_sync )],

   do => sub {
      my ( $http ) = @_;

      my ( $user, $room_id, $filter_id );

      my $filter = {};

      matrix_register_user_with_filter( $http, $filter )->then( sub {
         ( $user, $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_add_tag( $user, $room_id, "test_tag", { order => 1 } );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{joined}{$room_id};
         require_json_keys( $room, qw( private_user_data ) );

         check_private_user_data( $room->{private_user_data}{events} );

         Future->done( 1 );
      });
   };


test "Newly updated tags appear in an incremental v2 /sync",
   requires => [qw( first_api_client can_add_tag can_remove_tag can_sync )],

   do => sub {
      my ( $http ) = @_;

      my ( $user, $room_id, $filter_id, $next_batch );

      my $filter = {};

      matrix_register_user_with_filter( $http, $filter )->then( sub {
         ( $user, $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user, $filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         $next_batch = $body->{next_batch};

         matrix_add_tag( $user, $room_id, "test_tag", { order => 1 } );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id, since => $next_batch );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{joined}{$room_id};
         require_json_keys( $room, qw( private_user_data ) );

         check_private_user_data( $room->{private_user_data}{events} );

         Future->done( 1 );
      });
   };

test "Deleted tags appear in an incremental v2 /sync",
   requires => [qw( first_api_client can_add_tag can_remove_tag can_sync )],

   do => sub {
      my ( $http ) = @_;

      my ( $user, $room_id, $filter_id, $next_batch );

      my $filter = {};

      matrix_register_user_with_filter( $http, $filter )->then( sub {
         ( $user, $filter_id ) = @_;

         matrix_create_room( $user );
      })->then( sub {
         ( $room_id ) = @_;

         matrix_sync( $user, $filter => $filter_id );
      })->then( sub {
         my ( $body ) = @_;

         $next_batch = $body->{next_batch};

         matrix_add_tag( $user, $room_id, "test_tag", { order => 1 } );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id, since => $next_batch );
      })->then( sub {
         my ( $body ) = @_;

         $next_batch = $body->{next_batch};

         matrix_remove_tag( $user, $room_id, "test_tag" );
      })->then( sub {
         matrix_sync( $user, filter => $filter_id, since => $next_batch );
      })->then( sub {
         my ( $body ) = @_;

         my $room = $body->{rooms}{joined}{$room_id};
         require_json_keys( $room, qw( private_user_data ) );

         check_private_user_data( $room->{private_user_data}{events},
            expect_empty => 1,
         );

         Future->done( 1 );
      });
   };
