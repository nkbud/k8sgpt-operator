/*
Copyright 2023 The K8sGPT Authors.
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/
package k8sgpt

import (
	"os"

	corev1alpha1 "github.com/k8sgpt-ai/k8sgpt-operator/api/v1alpha1"
	"github.com/k8sgpt-ai/k8sgpt-operator/pkg/resources"
	v1 "k8s.io/api/apps/v1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

type ConfigureStep struct {
	next K8sGPT
}

func (step *ConfigureStep) execute(instance *K8sGPTInstance) (ctrl.Result, error) {
	var err error
	instance.logger.Info("starting ConfigureStep")

	if instance.K8sgptConfig.Spec.AI.BackOff == nil {
		err := step.configureBackoff(instance)
		if err != nil {
			return instance.R.FinishReconcile(err, false, instance.K8sgptConfig.Name, instance.K8sgptConfig)
		}
	}

	// Check and see if the instance is new or has a K8sGPT deployment in flight
	instance.k8sgptDeployment, err = step.getDeployment(instance)
	if err != nil {
		return instance.R.FinishReconcile(err, false, instance.K8sgptConfig.Name, instance.K8sgptConfig)
	}

	instance.hasReadyReplicas = instance.k8sgptDeployment.Status.AvailableReplicas != 0

	if !instance.hasReadyReplicas && os.Getenv("LOCAL_MODE") == "" {
		instance.logger.Info("k8sgpt server not running, waiting next sync")
		return instance.R.FinishReconcile(nil, false, instance.K8sgptConfig.Name, instance.K8sgptConfig)
	}

	instance.logger.Info("ending ConfigureStep")

	return step.next.execute(instance)
}

func (step *ConfigureStep) setNext(next K8sGPT) {
	step.next = next
}

func (step *ConfigureStep) configureBackoff(instance *K8sGPTInstance) error {
	instance.K8sgptConfig.Spec.AI.BackOff = &corev1alpha1.BackOff{
		Enabled:    false,
		MaxRetries: 5,
	}
	return instance.R.Update(instance.Ctx, instance.K8sgptConfig)
}

func (step *ConfigureStep) getDeployment(instance *K8sGPTInstance) (*v1.Deployment, error) {
	deployment := v1.Deployment{}

	err := instance.R.Get(instance.Ctx, client.ObjectKey{
		Namespace: instance.K8sgptConfig.Namespace,
		Name:      instance.K8sgptConfig.Name,
	}, &deployment)

	if client.IgnoreNotFound(err) != nil {
		return &deployment, err
	}

	err = resources.Sync(instance.Ctx, instance.R.Client, *instance.K8sgptConfig, resources.SyncOp)

	return &deployment, err
}
