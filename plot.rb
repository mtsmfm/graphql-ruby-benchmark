require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'

  gem 'matplotlib', require: 'matplotlib/pyplot'
  gem 'pry-byebug'
end

require 'pathname'
require 'json'

ROOT_DIR = Pathname.new(__dir__)

path = ROOT_DIR.join('results/result-2023-09-09T03:03:08+00:00.json')

raw_data = JSON.parse(path.read)

plt = Matplotlib::Pyplot

data = raw_data.sort_by { Gem::Version.new(_1['graphql_version']) }.map { _1.fetch_values('graphql_version', 'ips') }

xs = data.map(&:first)
ys = data.map(&:last)

plt.plot(xs, ys)
plt.grid
plt.xticks(rotation: 60)
plt.xlabel('GraphQL Ruby version')
plt.ylabel('Iterations per second')
plt.title('Version vs IPS (higher is better)')
plt.tight_layout
plt.savefig(ROOT_DIR.join("results/figs/#{path.basename.to_s.sub('.json', '.png')}").to_s)
