# How to set up SyTest for Dendrite

Change `server-0/database.yaml` to include the following:

```
args:                                                                                                                        
  database: dendrite                                                                                                         
  host: /var/run/postgresql                                                                                                  
type: pg                                                                                                                     
```

**Warning, these are settings for a development environment. Take care not to assign superuser roles willy nilly in production.** 

## Set up Postgres

(Omit `sudo -u postgres` from below commands if on MacOS):

To get into postgresql interpreter:

```
sudo -u postgres psql
```

Then create a role with your username:

```
CREATE ROLE "<username>" WITH SUPERUSER LOGIN;
```

Create necessary postgres databases:

```
sudo -u postgres createdb dendrite
sudo -u postgres createdb sytest_template
```

SyTest will expect Dendrite to be at `../dendrite` relative to Sytest's root directory. 

## Running Tests

Simply run the following to execute tests:

```
./run-tests.pl -I Dendrite::Monolith -W ../dendrite/sytest-whitelist -B ../dendrite/sytest-blacklist
```

## Useful flags

* `-W` applies a test whitelist file, one of which is currently kept up to date
  with what sytests Dendrite passes
  [here](https://github.com/matrix-org/dendrite/blob/master/sytest-whitelist)

* `-B` applies a test blacklist file, one of which is currently kept up to date
  with what sytests are currently flaky (fail *sometimes*) with Dendrite
  [here](https://github.com/matrix-org/dendrite/blob/master/sytest-blacklist)

* `-d` lets you set the path to Dendrite's `bin/` directory, in case it's
  somewhere other than `../dendrite/bin`
