Spree::Core::Engine.routes.append do
  namespace :chimpy, path: "" do
    resource :subscribers, only: [:create]
  end
end
