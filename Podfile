project 'MoveFeet.xcodeproj'
platform :ios, '17.0'

def ui_pods
  pod 'SnapKit'
  # pod 'JTAppleCalendar'
end

def data_pods
  pod 'Cache'
  pod 'CombineExt'
  pod 'CoreStore'
  pod 'CoreGPX'
end

target 'MoveFeet' do
  use_frameworks!

  ui_pods
  data_pods

  target 'UnitTests' do
    inherit! :search_paths
  end

end
# Xcode 27 refuses to build pods that target older iOS versions, and several
# of these (CoreStore, SnapKit, CoreGPX, Cache, CombineExt) still declare iOS 9+.
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |build_config|
      if build_config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'].to_f < 17.0
        build_config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
      end
    end
  end
end
