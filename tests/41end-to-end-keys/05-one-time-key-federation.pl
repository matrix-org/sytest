multi_test "Can claim remote one time key using POST",
    requires => [qw(
        remote_v2_users e2e_user_alice do_request_json_for e2e_can_upload_keys
    )],
    check => sub {
        my ($remote_users, $e2e_user_alice, $do_request_json_for) = @_;
        $do_request_json_for->(
            $e2e_user_alice,
            method => "POST",
            uri => "/keys/upload/alices_first_device",
            content => {
                one_time_keys => {
                    "test_algorithm:test_id", "test+base64+key"
                }
            }
        )->then(sub {
            pass "Uploaded one time keys";
            $do_request_json_for->(
                $e2e_user_alice,
                method => "GET",
                uri => "/keys/upload/alices_first_device"
            )
        })->then(sub {
            my ($content) = @_;
            require_json_keys($content, "one_time_key_counts");
            require_json_keys($content->{one_time_key_counts}, "test_algorithm");
            die "Expected 1 one time key"
                unless $content->{one_time_key_counts}{test_algorithm} eq 1;
            pass "Counted one time keys";
            $do_request_json_for->(
                $remote_users->[0],
                method => "POST",
                uri => "/keys/claim",
                content => {
                    one_time_keys => {
                        $e2e_user_alice->user_id => {
                            alices_first_device => "test_algorithm"
                        }
                    }
                }
            )
        })->then(sub {
            my ($content) = @_;
            require_json_keys($content, "one_time_keys");
            my $one_time_keys = $content->{one_time_keys};
            require_json_keys($one_time_keys, $e2e_user_alice->user_id);
            my $alice_keys = $one_time_keys->{$e2e_user_alice->user_id};
            require_json_keys($alice_keys, "alices_first_device");
            my $alice_device_keys = $alice_keys->{alices_first_device};
            require_json_keys($alice_device_keys, "test_algorithm:test_id");
            die "Unexpected key base64" unless "test+base64+key" eq
                $alice_device_keys->{"test_algorithm:test_id"};
            pass "Took one time key";
            $do_request_json_for->(
                $e2e_user_alice,
                method => "GET",
                uri => "/keys/upload/alices_first_device"
            )
        })->then(sub {
            my ($content) = @_;
            require_json_keys($content, "one_time_key_counts");
            exists $content->{one_time_key_counts}->{"test_algorithm"} and
                die "Expected that the key would be removed from the counts";
            Future->done(1)
        });
    }
