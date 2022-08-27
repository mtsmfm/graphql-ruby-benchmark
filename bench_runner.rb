require "bundler/inline"

gemfile do
  source "https://rubygems.org"

  gem "pry-byebug"
  gem "facter"
end

require "open3"
require "json"
require "logger"
require "time"
require "pathname"

ROOT_DIR = Pathname.new(__dir__)
RESULTS_DIR = ROOT_DIR.join("results")

class BenchmarkRunner
  SECONDS = 30
  GRAPHQL_VERSIONS = ["2.0.13", "2.0.12", "2.0.11", "2.0.9", "2.0.8", "2.0.7", "2.0.6", "2.0.5", "2.0.4", "2.0.3", "2.0.2", "2.0.1", "2.0.0", "1.13.15", "1.13.14", "1.13.13", "1.13.12", "1.13.11", "1.13.10", "1.13.9", "1.13.8", "1.13.7", "1.13.6", "1.13.5", "1.13.4", "1.13.3", "1.13.2", "1.13.1", "1.13.0", "1.12.24", "1.12.23", "1.12.22", "1.12.21", "1.12.20", "1.12.19", "1.12.18", "1.12.17", "1.12.16", "1.12.15", "1.12.14", "1.12.13", "1.12.12", "1.12.11", "1.12.10", "1.12.9", "1.12.8", "1.12.7", "1.12.6", "1.12.5", "1.12.4", "1.12.3", "1.12.2", "1.12.1", "1.12.0", "1.11.10", "1.11.9", "1.11.8", "1.11.7", "1.11.6", "1.11.5", "1.11.4", "1.11.3", "1.11.2", "1.11.1", "1.11.0", "1.10.14", "1.10.13", "1.10.12", "1.10.11", "1.10.10", "1.10.9", "1.10.8", "1.10.7", "1.10.6", "1.10.5", "1.10.4", "1.10.3", "1.10.2", "1.10.1", "1.10.0", "1.9.21", "1.9.20", "1.9.19", "1.9.18", "1.9.17", "1.9.16", "1.9.15", "1.9.14", "1.9.13", "1.9.12", "1.9.11", "1.9.10", "1.9.9", "1.9.8", "1.9.7", "1.9.6", "1.9.5", "1.9.4", "1.9.3", "1.9.2", "1.9.1", "1.9.0", "1.8.18", "1.8.17", "1.8.16", "1.8.15", "1.8.14", "1.8.13", "1.8.12", "1.8.11", "1.8.10", "1.8.9", "1.8.8", "1.8.7", "1.8.6", "1.8.5", "1.8.4", "1.8.3", "1.8.2", "1.8.1", "1.8.0", "1.7.14", "1.7.13", "1.7.12", "1.7.11", "1.7.10", "1.7.9", "1.7.8", "1.7.7", "1.7.6", "1.7.5", "1.7.4", "1.7.3", "1.7.2", "1.7.1", "1.7.0", "1.6.8", "1.6.7", "1.6.6", "1.6.5", "1.6.4", "1.6.3", "1.6.2", "1.6.1", "1.6.0", "1.5.15", "1.5.14", "1.5.13", "1.5.12", "1.5.11", "1.5.10", "1.5.9", "1.5.8", "1.5.7.1", "1.5.7", "1.5.6", "1.5.5", "1.5.4", "1.5.3", "1.4.5", "1.4.4", "1.4.3", "1.4.2", "1.4.1", "1.4.0", "1.3.0", "1.2.6", "1.2.5", "1.2.4", "1.2.3", "1.2.2", "1.2.1", "1.2.0", "1.1.0", "1.0.0", "0.19.4", "0.19.3", "0.19.2", "0.19.1", "0.19.0", "0.18.15", "0.18.14", "0.18.13", "0.18.12", "0.18.11", "0.18.10", "0.18.9", "0.18.8", "0.18.7", "0.18.6", "0.18.5", "0.18.4", "0.18.3", "0.18.2", "0.18.1", "0.18.0", "0.17.2", "0.17.1", "0.17.0", "0.16.1", "0.16.0", "0.15.3", "0.15.2", "0.15.1", "0.15.0", "0.14.2", "0.14.1", "0.14.0", "0.13.0", "0.12.1", "0.12.0", "0.11.1", "0.11.0", "0.10.9", "0.10.8", "0.10.7", "0.10.6", "0.10.5", "0.10.4", "0.10.3", "0.10.2", "0.10.1", "0.10.0", "0.9.5", "0.9.4", "0.9.3", "0.9.2", "0.8.1", "0.8.0", "0.7.1", "0.7.0", "0.6.2", "0.6.1", "0.6.0", "0.5.0", "0.4.0", "0.3.0", "0.2.0", "0.1.0", "0.0.4", "0.0.3", "0.0.2", "0.0.1"]

  LOGGER = Logger.new(STDOUT)

  def run
    latest_patch_versions = GRAPHQL_VERSIONS.map { Gem::Version.new(_1) }.select { _1 >= Gem::Version.new("0.1.0") }.group_by { _1.version.split(".")[0, 2] }.transform_values(&:max).values
    latest_version = latest_patch_versions.max.version

    result = latest_patch_versions.map(&:version).first(1).flat_map do |graphql_version|
      LOGGER.info("Start benchmark for #{graphql_version}")

      matrix = if graphql_version == latest_version
        [
          {field_count: 1, object_count: 1000},
          {field_count: 10, object_count: 1000},
          {field_count: 100, object_count: 1000},
          {field_count: 300, object_count: 1000},
          {field_count: 500, object_count: 1000},
          {field_count: 700, object_count: 1000},
          {field_count: 1000, object_count: 1000},
          {field_count: 100, object_count: 1},
          {field_count: 100, object_count: 10},
          {field_count: 100, object_count: 100},
          {field_count: 100, object_count: 1000},
          {field_count: 100, object_count: 10000},
          {field_count: 100, object_count: 100000},
        ]
      else
        [
          {field_count: 100, object_count: 1000}
        ]
      end

      matrix.map do |field_count:, object_count:|
        LOGGER.info("field_count: #{field_count}, object_count: #{object_count}")

        result = benchmark(graphql_version: graphql_version, field_count: field_count, object_count: object_count, seconds: SECONDS)

        {
          ruby_version: RUBY_VERSION,
          graphql_version: graphql_version,
          field_count: field_count,
          object_count: object_count,
          iteration_count: result[:iteration_count],
          time: result[:time],
          ips: result[:iteration_count] / result[:time],
          processors: Facter["processors"].value,
        }
      end
    end

    RESULTS_DIR.join("result-#{Time.now.iso8601}.json").write(JSON.pretty_generate(result))
  end

  private

  def benchmark(graphql_version:, field_count:, object_count:, seconds:)
    read, write = IO.pipe
    pid = Process.fork do
      ENV["GRAPHQL_VERSION"] = graphql_version
      ENV["FIELD_COUNT"] = field_count.to_s
      ENV["OBJECT_COUNT"] = object_count.to_s

      load ROOT_DIR.join("graphql.rb")

      iteration_count = 0
      started_at = Time.now
      time = nil

      loop do
        execute
        iteration_count += 1
        time = Time.now - started_at
        break if time >= seconds
      end

      write.puts iteration_count
      write.puts time
    end

    _, status = Process.waitpid2(pid, 0)
    unless status.success?
      raise "Something wrong"
    end
    write.close
    result = read.read
    read.close
    iteration_count, time = result.lines(chomp: true)
    {
      iteration_count: iteration_count.to_i,
      time: time.to_f
    }
  end
end

BenchmarkRunner.new.run
