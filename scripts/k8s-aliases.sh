# Base
alias k='kubectl'
alias kg='kubectl get'
alias kd='kubectl describe'
alias kdel='kubectl delete'
alias ka='kubectl apply -f'
alias kaf='kubectl apply -f'
alias krm='kubectl delete -f'

# Namespaces
alias kgn='kubectl get ns'
alias kcn='kubectl config set-context --current --namespace'

# Wide & yaml
alias kgw='kubectl get -o wide'
alias kgy='kubectl get -o yaml'
alias kgj='kubectl get -o json'

# Pods
alias kgp='kubectl get pods'
alias kgpw='kubectl get pods -o wide'
alias kgpn='kubectl get pods -n'
alias kdp='kubectl describe pod'
alias kdelp='kubectl delete pod'
alias kdelpn='kubectl delete pod -n'
alias klogs='kubectl logs'
alias klogsf='kubectl logs -f'
alias kexec='kubectl exec -it'

# Deployment & Service
alias kgd='kubectl get deploy'
alias kdd='kubectl describe deploy'
alias kgs='kubectl get svc'
alias kgsvc='kubectl get svc -o wide'

# Node & Cluster
alias kgnode='kubectl get nodes -o wide'
alias kdnode='kubectl describe node'
alias kctx='kubectl config get-contexts'
alias kuse='kubectl config use-context'

# Debug
alias ktop='kubectl top pods'
alias ktopn='kubectl top nodes'
alias kevents='kubectl get events --sort-by=.metadata.creationTimestamp'

# Productivity
alias kgall='kubectl get all'
alias krestart='kubectl rollout restart deployment'
alias kstatus='kubectl rollout status deployment'
