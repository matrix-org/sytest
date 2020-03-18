# check that the rules around server_names are enforced

test "Non-numeric ports in server names are rejected",
   requires => [ $main::HOMESERVER_INFO[0], local_user_fixture(), ],

   do => sub {
      my ( $info, $user ) = @_;

      my ( $pkey, $skey ) = Crypt::NaCl::Sodium->sign->keypair;

      my $datastore = SyTest::Federation::Datastore->new(
         server_name => "localhost:http",
         key_id      => "ed25519:1",
         public_key  => $pkey,
         secret_key  => $skey,
      );

      my $outbound_client = SyTest::Federation::Client->new(
         datastore => $datastore,
         uri_base  => "/_matrix/federation/v1",
        );
      $loop->add( $outbound_client );

      $outbound_client->do_request_json(
         method   => "GET",
         hostname => $info->server_name,
         uri      => "/query/profile",

         params => {
            user_id => $user->user_id,
            field   => "displayname",
         }
      )->main::expect_http_400();
   };
