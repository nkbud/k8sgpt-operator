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

package main

import (
	"context"
	"flag"
	"fmt"
	"math/rand"
	"os"
	"time"

	"github.com/k8sgpt-ai/k8sgpt-operator/internal/controller/k8sgpt"
	"github.com/k8sgpt-ai/k8sgpt-operator/internal/controller/mutation"
	"github.com/k8sgpt-ai/k8sgpt-operator/internal/controller/types"

	// Import all Kubernetes client auth plugins (e.g. Azure, GCP, OIDC, etc.)
	// to ensure that exec-entrypoint and run can make use of them.
	_ "k8s.io/client-go/plugin/pkg/client/auth"

	corev1alpha1 "github.com/k8sgpt-ai/k8sgpt-operator/api/v1alpha1"
	"github.com/k8sgpt-ai/k8sgpt-operator/pkg/integrations"
	"github.com/k8sgpt-ai/k8sgpt-operator/pkg/metrics"
	"github.com/k8sgpt-ai/k8sgpt-operator/pkg/sinks"
	"k8s.io/apimachinery/pkg/runtime"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/healthz"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"
	"sigs.k8s.io/controller-runtime/pkg/webhook"
	//+kubebuilder:scaffold:imports
)

var (
	scheme   = runtime.NewScheme()
	setupLog = ctrl.Log.WithName("setup")
)

func init() {
	utilruntime.Must(clientgoscheme.AddToScheme(scheme))

	utilruntime.Must(corev1alpha1.AddToScheme(scheme))
	//+kubebuilder:scaffold:scheme
}

func main() {
	var metricsAddr string
	var enableLeaderElection bool
	var probeAddr string
	var enableResultLogging bool
	flag.StringVar(&metricsAddr, "metrics-bind-address", ":8080", "The address the metric endpoint binds to.")
	flag.StringVar(&probeAddr, "health-probe-bind-address", ":8081", "The address the probe endpoint binds to.")
	flag.BoolVar(&enableResultLogging, "enable-result-logging", false, "Whether to enable results logging")
	flag.BoolVar(&enableLeaderElection, "leader-elect", false,
		"Enable leader election for controller manager. "+
			"Enabling this will ensure there is only one active controller manager.")
	opts := zap.Options{
		Development: true,
	}
	opts.BindFlags(flag.CommandLine)
	flag.Parse()

	ctrl.SetLogger(zap.New(zap.UseFlagOptions(&opts)))
	if os.Getenv("LOCAL_MODE") != "" {
		setupLog.Info("Running in local mode")
		min := 7000
		max := 8000
		metricsAddr = fmt.Sprintf(":%d", rand.Intn(max-min+1)+min)
		probeAddr = fmt.Sprintf(":%d", rand.Intn(max-min+1)+min)
		setupLog.Info(fmt.Sprintf("Metrics address: %s", metricsAddr))
		setupLog.Info(fmt.Sprintf("Probe address: %s", probeAddr))
	}
	mgr, err := ctrl.NewManager(ctrl.GetConfigOrDie(), ctrl.Options{
		Scheme: scheme,
		Metrics: metricsserver.Options{
			BindAddress: metricsAddr,
		},
		WebhookServer: webhook.NewServer(webhook.Options{
			Port: 9443,
		}),
		HealthProbeBindAddress: probeAddr,
		LeaderElection:         enableLeaderElection,
		LeaderElectionID:       "ea9c19f7.k8sgpt.ai",
		// LeaderElectionReleaseOnCancel defines if the leader should step down voluntarily
		// when the Manager ends. This requires the binary to immediately end when the
		// Manager is stopped, otherwise, this setting is unsafe. Setting this significantly
		// speeds up voluntary leader transitions as the new leader don't have to wait
		// LeaseDuration time first.
		//
		// In the default scaffold provided, the program ends immediately after
		// the manager stops, so would be fine to enable this option. However,
		// if you are doing or is intended to do any operation such as perform cleanups
		// after the manager stops then its usage might be unsafe.
		// LeaderElectionReleaseOnCancel: true,
	})
	if err != nil {
		setupLog.Error(err, "unable to start manager")
		os.Exit(1)
	}

	integration, err := integrations.NewIntegrations(mgr.GetClient(), context.Background())
	if err != nil {
		setupLog.Error(err, "unable to create REST client to initialise Integrations")
		os.Exit(1)
	}

	timeout, exists := os.LookupEnv("OPERATOR_SINK_WEBHOOK_TIMEOUT_SECONDS")
	if !exists {
		timeout = "35s"
	}

	sinkTimeout, err := time.ParseDuration(timeout)
	if err != nil {
		setupLog.Error(err, "unable to read webhook timeout value")
		os.Exit(1)
	}
	sinkClient := sinks.NewClient(sinkTimeout)

	metricsBuilder := metrics.InitializeMetrics()

	// This channel allows us to indicate when K8sGPT deployment is ready for active comms
	// This is a necessity for the mutation system to work
	ready := make(chan types.InterControllerSignal, 10)

	if err = (&mutation.MutationReconciler{
		Client:         mgr.GetClient(),
		Scheme:         mgr.GetScheme(),
		MetricsBuilder: metricsBuilder,
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "unable to create controller", "controller", "Mutation")
		os.Exit(1)
	}

	if err = (&k8sgpt.K8sGPTReconciler{
		Client:              mgr.GetClient(),
		Scheme:              mgr.GetScheme(),
		Signal:              ready,
		Integrations:        integration,
		SinkClient:          sinkClient,
		MetricsBuilder:      metricsBuilder,
		EnableResultLogging: enableResultLogging,
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "unable to create controller", "controller", "K8sGPT")
		os.Exit(1)
	}
	//+kubebuilder:scaffold:builder

	if err := mgr.AddHealthzCheck("healthz", healthz.Ping); err != nil {
		setupLog.Error(err, "unable to set up health check")
		os.Exit(1)
	}
	if err := mgr.AddReadyzCheck("readyz", healthz.Ping); err != nil {
		setupLog.Error(err, "unable to set up ready check")
		os.Exit(1)
	}

	setupLog.Info("starting manager")
	if err := mgr.Start(ctrl.SetupSignalHandler()); err != nil {
		setupLog.Error(err, "problem running manager")
		os.Exit(1)
	}
}
