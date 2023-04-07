module BulletTrain
  module Themes
    module Densha
      class Engine < ::Rails::Engine
        initializer "bullet_train.themes.densha.register" do |app|
          BulletTrain::Themes.themes[:densha] = BulletTrain::Themes::Densha::Theme.new
          BulletTrain.linked_gems << "bullet_train-themes-densha"
        end
      end
    end
  end
end
