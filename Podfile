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