ec2-backup
==========

Automate backups of your infrastructure dynamically via AWS EC2 Tagging and Snapshots

Installation
==========

`gem install ec2-backup`

Configuration
==========

* accounts - An array of accounts you wish to configure backups for

Each account has a key for the name of the account followed by the
`access_key_id` and `secret_access_key` for the account

* hourly_snapshots - The amount of hourly snapshots to retain
* daily_snapshots - The amount of daily snapshots to retain
* weekly_snapshots - The amount of weekly snapshots to retain
* monthly_snapshots - The amount of monthly snapshots to retain

* tags - The AWS EC2 Tags used for finding instances to be snapshotted.

Usage
==========

Create a `ec2-backup.yml` as shown in the example file in the repository
and place it in your home directory as `.ec2-backup.yml`

When you're ready to start backing up your instances, execute the
`ec2-backup` command from your terminal.
