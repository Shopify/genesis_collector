# genesis_collector

This gem is a small utility that will collect information about your hardware server for the purpose of sending it back to a Genesis server.

## Installation

Install it:

    $ gem install genesis_collector

## Usage

This gem ships with a command line tool to show you the data it collects. Simply run `genesis_collector` and you will see all the data. This command does not send any data anywhere.

This gem also ships with a Chef handler which will collect and send the data.

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Shopify/genesis_collector.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
